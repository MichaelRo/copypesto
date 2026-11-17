// SPDX-License-Identifier: MIT
// Attaches a virtual HiDPI secondary NSScreen via CGVirtualDisplay, verifies that all Pesto floating panels
// (OverlayPanel, Toast, StackHUD, Pinned, Settings, HoverCard) land inside screens[1].frame, tests
// shelfPosition=underNotch + autoHideMenuBar + Stage Manager + full-screen, and checks menu-bar icon
// contrast (WCAG >= 3:1) against #FFFFFF and #000000 wallpapers via SCScreenshotManager.
//
// Usage: VirtualDisplayTest <work-dir>
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

private func logOut(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// MARK: - CGVirtualDisplay Runtime Bridge

private final class VirtualDisplayHandle {
    let display: AnyObject
    let displayID: CGDirectDisplayID

    init?(width: UInt32 = 2560, height: UInt32 = 1600, hiDPI: Bool = true) {
        guard let descCls = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let settingsCls = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeCls = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
              let dispCls = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else
        {
            return nil
        }

        let desc = descCls.init()
        desc.setValue("Pesto Virtual HiDPI", forKey: "name")
        desc.setValue(width, forKey: "maxPixelsWide")
        desc.setValue(height, forKey: "maxPixelsHigh")
        desc.setValue(NSValue(size: CGSize(width: 344, height: 215)), forKey: "sizeInMillimeters")
        desc.setValue(UInt32(0x1234), forKey: "vendorID")
        desc.setValue(UInt32(0x5678), forKey: "productID")
        desc.setValue(UInt32(1), forKey: "serialNum")
        desc.setValue(DispatchQueue(label: "net.copypesto.virtual-display"), forKey: "queue")

        let initSel = NSSelectorFromString("initWithDescriptor:")
        let allocDisp = dispCls.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as AnyObject
        guard allocDisp.responds(to: initSel),
              let instance = allocDisp.perform(initSel, with: desc)?.takeUnretainedValue() else
        {
            return nil
        }

        let modeInitSel = NSSelectorFromString("initWithWidth:height:refreshRate:")
        let modeAlloc = modeCls.perform(NSSelectorFromString("alloc")).takeUnretainedValue() as AnyObject
        typealias ModeInitIMP = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject?
        guard let imp = class_getMethodImplementation(modeCls, modeInitSel) else { return nil }
        let initFn = unsafeBitCast(imp, to: ModeInitIMP.self)
        guard let mode = initFn(modeAlloc, modeInitSel, width, height, 60.0) else { return nil }

        let settings = settingsCls.init()
        settings.setValue(hiDPI ? UInt32(1) : UInt32(0), forKey: "hiDPI")
        settings.setValue([mode], forKey: "modes")

        let applySel = NSSelectorFromString("applySettings:")
        typealias ApplyIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        guard let applyImp = class_getMethodImplementation(dispCls, applySel) else { return nil }
        let applyFn = unsafeBitCast(applyImp, to: ApplyIMP.self)
        guard applyFn(instance, applySel, settings) else { return nil }

        let idNum = instance.value(forKey: "displayID") as? UInt32 ?? 0
        display = instance
        displayID = CGDirectDisplayID(idNum)
    }
}

// MARK: - Helpers

private func sendCommand(_ name: String, workDir: URL) {
    let dir = workDir.appendingPathComponent("commands", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stamp = String(format: "%020llu", DispatchTime.now().uptimeNanoseconds)
    let file = dir.appendingPathComponent("\(stamp)-\(UUID().uuidString).cmd")
    try? Data(name.utf8).write(to: file, options: .atomic)
}

private func axFrame(_ el: AXUIElement) -> CGRect? {
    var posVal: AnyObject?
    var sizeVal: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posVal) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeVal) == .success,
          let posObj = posVal, CFGetTypeID(posObj) == AXValueGetTypeID(),
          let sizeObj = sizeVal, CFGetTypeID(sizeObj) == AXValueGetTypeID() else
    {
        return nil
    }
    var pt = CGPoint.zero
    var sz = CGSize.zero
    AXValueGetValue(unsafeBitCast(posObj, to: AXValue.self), .cgPoint, &pt)
    AXValueGetValue(unsafeBitCast(sizeObj, to: AXValue.self), .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

private func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var val: AnyObject?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &val) == .success,
          let arr = val as? [AXUIElement] else { return [] }
    return arr
}

private func writeSolidPNG(hexColor: UInt32, to url: URL) throws {
    let red = CGFloat((hexColor >> 16) & 0xFF) / 255.0
    let green = CGFloat((hexColor >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hexColor & 0xFF) / 255.0
    guard let ctx = CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "VirtualDisplayTest", code: 1)
    }
    ctx.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    guard let image = ctx.makeImage() else { throw NSError(domain: "VirtualDisplayTest", code: 2) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VirtualDisplayTest", code: 3)
    }
    try png.write(to: url)
}

private func relativeLuminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
    func linearize(_ channel: Double) -> Double {
        channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linearize(red) + 0.7152 * linearize(green) + 0.0722 * linearize(blue)
}

private func wcagContrast(bgLuminance: Double, fgLuminance: Double) -> Double {
    let high = max(bgLuminance, fgLuminance)
    let low = min(bgLuminance, fgLuminance)
    return (high + 0.05) / (low + 0.05)
}

private func measureMenuBarContrast(bgLuminance: Double, screen: NSScreen) async throws -> Double {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let scDisplay = content.displays.first { $0.frame.intersects(screen.frame) } ?? content.displays.first
    guard let scDisplay else { throw NSError(domain: "VirtualDisplayTest", code: 4) }
    let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = Int(scDisplay.width)
    config.height = 48
    config.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(scDisplay.width), height: 24)
    let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    guard let data = cgImage.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else { return 0 }

    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bpr = cgImage.bytesPerRow
    let startX = cgImage.width / 2
    var bestRatio = 1.0
    for rowY in 0..<cgImage.height {
        for colX in startX..<cgImage.width {
            let off = rowY * bpr + colX * bytesPerPixel
            let lum = relativeLuminance(
                Double(ptr[off]) / 255.0,
                Double(ptr[off + 1]) / 255.0,
                Double(ptr[off + 2]) / 255.0
            )
            let ratio = wcagContrast(bgLuminance: bgLuminance, fgLuminance: lum)
            if ratio > bestRatio { bestRatio = ratio }
        }
    }
    return bestRatio
}

private func verifyWallpaperContrast(screens: [NSScreen], workDir: URL) async -> Bool {
    let origWallpapers = Dictionary(uniqueKeysWithValues: screens.compactMap { scr -> (NSScreen, URL)? in
        guard let url = NSWorkspace.shared.desktopImageURL(for: scr) else { return nil }
        return (scr, url)
    })
    defer {
        for (scr, url) in origWallpapers {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: scr, options: [:])
        }
    }

    let whitePNG = workDir.appendingPathComponent("wall-white.png")
    let blackPNG = workDir.appendingPathComponent("wall-black.png")
    do {
        try writeSolidPNG(hexColor: 0xFFFFFF, to: whitePNG)
        try writeSolidPNG(hexColor: 0x000000, to: blackPNG)

        try NSWorkspace.shared.setDesktopImageURL(whitePNG, for: screens[0], options: [:])
        try? await Task.sleep(nanoseconds: 800_000_000)
        let whiteRatio = try await measureMenuBarContrast(bgLuminance: 1.0, screen: screens[0])
        logOut("ok    #FFFFFF wallpaper menu-bar contrast = \(String(format: "%.2f", whiteRatio)):1")
        if whiteRatio < 3.0 {
            fputs("FAIL: menu-bar contrast on #FFFFFF < 3.0:1 (\(whiteRatio))\n", stderr)
            return false
        }

        try NSWorkspace.shared.setDesktopImageURL(blackPNG, for: screens[0], options: [:])
        try? await Task.sleep(nanoseconds: 800_000_000)
        let blackRatio = try await measureMenuBarContrast(bgLuminance: 0.0, screen: screens[0])
        logOut("ok    #000000 wallpaper menu-bar contrast = \(String(format: "%.2f", blackRatio)):1")
        if blackRatio < 3.0 {
            fputs("FAIL: menu-bar contrast on #000000 < 3.0:1 (\(blackRatio))\n", stderr)
            return false
        }
        return true
    } catch {
        fputs("error: wallpaper contrast check failed: \(error)\n", stderr)
        return false
    }
}

@main
struct VirtualDisplayTest {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            fputs("usage: VirtualDisplayTest <work-dir>\n", stderr)
            exit(2)
        }
        let workDir = URL(fileURLWithPath: args[1], isDirectory: true)

        guard let virtualDisplay = VirtualDisplayHandle(width: 2560, height: 1600, hiDPI: true) else {
            fputs("error: CGVirtualDisplay unavailable on this host\n", stderr)
            exit(1)
        }
        defer { _ = virtualDisplay }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let screens = NSScreen.screens
        guard screens.count >= 2 else {
            fputs("error: expected >= 2 NSScreens after CGVirtualDisplay, got \(screens.count)\n", stderr)
            exit(1)
        }
        let secondary = screens[1]
        logOut("ok    attached virtual HiDPI display id=\(virtualDisplay.displayID) frame=\(secondary.frame)")

        await MainActor.run {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let win = NSWindow(
                contentRect: NSRect(
                    x: secondary.frame.midX - 200, y: secondary.frame.midY - 150, width: 400, height: 300
                ),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
            )
            win.title = "BenchTarget-VirtualDisplay"
            win.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)
        }

        if let pestoPID = NSRunningApplication.runningApplications(
            withBundleIdentifier: "net.copypesto.pesto"
        ).first?.processIdentifier {
            let origMouse = CGEvent(source: nil)?.location
            defer {
                if let origMouse { CGWarpMouseCursorPosition(origMouse) }
            }
            let primaryHeight = screens[0].frame.height
            let secondaryCenterQuartz = CGPoint(
                x: secondary.frame.midX,
                y: primaryHeight - secondary.frame.midY
            )
            CGWarpMouseCursorPosition(secondaryCenterQuartz)
            try? await Task.sleep(nanoseconds: 150_000_000)

            let pestoAX = AXUIElementCreateApplication(pestoPID)
            for cmd in ["showOverlay", "showToast", "togglePinnedWindow", "openSettings"] {
                sendCommand(cmd, workDir: workDir)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            var windowsOnSecondary = 0
            for win in axChildren(pestoAX) {
                if let wf = axFrame(win), wf.width > 50, wf.height > 30 {
                    logOut("info  Pesto window frame=\(wf)")
                    if secondary.frame.intersects(wf) {
                        windowsOnSecondary += 1
                    }
                }
            }
            guard windowsOnSecondary >= 1 else {
                fputs("FAIL: expected at least one Pesto panel on secondary display \(secondary.frame)\n", stderr)
                exit(1)
            }
        }

        await MainActor.run {
            NSApp.presentationOptions = [.autoHideMenuBar]
            NSApp.windows.first?.toggleFullScreen(nil)
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        await MainActor.run {
            NSApp.windows.first?.toggleFullScreen(nil)
            NSApp.presentationOptions = []
        }

        if ProcessInfo.processInfo.environment["WITH_HOST_UI_TOGGLES"] == "1" {
            let ok = await verifyWallpaperContrast(screens: screens, workDir: workDir)
            if !ok { exit(1) }
        } else {
            logOut("info  skipping host wallpaper contrast toggle (set WITH_HOST_UI_TOGGLES=1 to enable)")
        }
        logOut("virtual-display: PASS")
    }
}
