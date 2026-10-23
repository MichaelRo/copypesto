// SPDX-License-Identifier: MIT
import AppKit

public struct SourceAppRecord: Sendable, Equatable {
    public let bundleID: String
    public let displayName: String
    /// 48×48 PNG, ≤5 KB. Shared through `SourceIconCache`; ingest does not use it.
    public let iconData: Data
    /// Hex `"#RRGGBB"` — drives the overlay mesh-gradient glow.
    public let dominantColorHex: String

    public init(bundleID: String, displayName: String, iconData: Data, dominantColorHex: String) {
        self.bundleID = bundleID
        self.displayName = displayName
        self.iconData = iconData
        self.dominantColorHex = dominantColorHex
    }
}

/// Resolves a bundle ID to a small, cacheable record containing the app's display name,
/// downscaled icon (48×48 PNG), and dominant icon color. Resolution happens at ingest time
/// — never at render — because the frontmost app may have changed by then. The drawing is AppKit image work, so it
/// runs on the main actor, and `SourceIconCache` holds it so that ingest and the cards draw an app once between them.
public actor SourceAppResolver {
    public static let iconPixelDimension: Int = 48
    /// The size the icon is drawn at once to read both its thumbnail and its colour.
    private static let sampleDimension = 96

    private var cache: [String: SourceAppRecord] = [:]
    private let icons: SourceIconCache?

    /// `icons` is the cache the drawing comes from; nil is the app's shared one.
    public init(icons: SourceIconCache? = nil) {
        self.icons = icons
    }

    @MainActor
    private static func drawnRecord(bundleID: String, in icons: SourceIconCache?) -> SourceAppRecord {
        (icons ?? SourceIconCache.shared).record(for: bundleID)
    }

    public func resolve(bundleID: String) async -> SourceAppRecord {
        if let cached = cache[bundleID] { return cached }
        let record = await Self.drawnRecord(bundleID: bundleID, in: icons)
        cache[bundleID] = record
        return record
    }

    public func invalidate(bundleID: String) {
        cache.removeValue(forKey: bundleID)
    }

    /// Friendly names for macOS system daemons that don't ship with a normal app bundle.
    /// Surfacing the raw bundle ID (e.g. "com.apple.SecurityAgent") looks like a bug to
    /// the user — they're usually copying from a Touch ID prompt or system sheet.
    private static let systemDisplayNames: [String: String] = [
        "com.apple.SecurityAgent": "System Authentication",
        "com.apple.coreservicesd": "System Services",
        "com.apple.WindowManager": "Window Manager",
        "com.apple.controlcenter": "Control Center",
        "com.apple.systemuiserver": "System UI",
        "com.apple.universalaccessAuthWarn": "Accessibility"
    ]

    @MainActor
    static func computeRecord(bundleID: String) -> SourceAppRecord {
        let workspace = NSWorkspace.shared
        let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID)
        let icon = appURL.map { workspace.icon(forFile: $0.path) } ?? workspace.icon(forFile: "/")
        let displayName: String = {
            if let override = systemDisplayNames[bundleID] { return override }
            // A bundle ID macOS can't resolve — a defunct ID, or the app has since been
            // uninstalled — falls back to a plain name rather than the raw identifier, which
            // reads as unlabelled/technical wherever it is shown.
            guard let url = appURL,
                  let bundle = Bundle(url: url) else { return "Unknown app" }
            return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? "Unknown app"
        }()
        let raster = rasterized(icon, side: sampleDimension)
        let pngData = raster.flatMap { downscalePNG($0, side: iconPixelDimension) } ?? Data()
        let color = raster.map { dominantColorHex(of: $0, samples: 96) } ?? "#888888"

        return SourceAppRecord(
            bundleID: bundleID,
            displayName: displayName,
            iconData: pngData,
            dominantColorHex: color
        )
    }

    /// The icon drawn once at `side`×`side` pixels. An app icon holds several sizes up to 1024 points at 2×, and
    /// `tiffRepresentation` encodes all of them: 64 MB per icon, built the first time the shelf shows that app.
    /// Drawing asks the image for the one size it needs.
    @MainActor
    private static func rasterized(_ icon: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        return rep
    }

    @MainActor
    private static func downscalePNG(_ raster: NSBitmapImageRep, side: Int) -> Data? {
        guard let source = raster.cgImage else { return nil }
        let scaled: CGImage
        if raster.pixelsWide == side {
            scaled = source
        } else {
            guard let context = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            guard let image = context.makeImage() else { return nil }
            scaled = image
        }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [.compressionFactor: 0.85])
    }

    /// Coarse dominant-color extraction: sample the icon's pixels and average the
    /// brightest cluster. Good enough for an ambient glow; not photometrically correct.
    @MainActor
    private static func dominantColorHex(of rep: NSBitmapImageRep, samples: Int) -> String {
        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        guard width > 0, height > 0 else { return "#888888" }

        // Sample on a uniform grid.
        let stride = max(1, Int(Double(width * height).squareRoot() / Double(samples)))
        var rSum: Double = 0
        var gSum: Double = 0
        var bSum: Double = 0
        var weight: Double = 0

        for y in Swift.stride(from: 0, to: height, by: stride) {
            for x in Swift.stride(from: 0, to: width, by: stride) {
                guard let color = rep.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.deviceRGB) else { continue }
                let a = Double(rgb.alphaComponent)
                if a < 0.5 { continue } // ignore transparent pixels
                let r = Double(rgb.redComponent)
                let g = Double(rgb.greenComponent)
                let b = Double(rgb.blueComponent)
                // Weight by saturation × brightness so we favor brand colors over neutral fills.
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                let weightSample = (0.5 + saturation) * maxC
                rSum += r * weightSample
                gSum += g * weightSample
                bSum += b * weightSample
                weight += weightSample
            }
        }
        guard weight > 0 else { return "#888888" }
        let r = Int((rSum / weight) * 255)
        let g = Int((gSum / weight) * 255)
        let b = Int((bSum / weight) * 255)
        return String(format: "#%02X%02X%02X", min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }
}
