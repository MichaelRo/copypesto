#!/usr/bin/env swift
// SPDX-License-Identifier: MIT
// Composites the installer window preview image (docs/images/installer.png):
// the DMG background, the Pesto Basil brand icon, and the Applications folder icon.
import AppKit
import CoreGraphics
import ImageIO

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = here.deletingLastPathComponent()

let bgScript = here.appendingPathComponent("make-dmg-background.swift").path
let tempBg = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("pesto-dmg-bg-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: tempBg) }

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = [bgScript, tempBg.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0,
      let bgImage = NSImage(contentsOf: tempBg) else
{
    fatalError("Failed to render DMG background")
}

let basilPath = root.appendingPathComponent("Sources/Resources/Assets.xcassets/AppIconBasil.imageset/AppIconBasil.png")
    .path
guard let basilIcon = NSImage(contentsOfFile: basilPath) else {
    fatalError("Missing AppIconBasil.png at \(basilPath)")
}

let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")

let width: CGFloat = 660
let height: CGFloat = 400
let scale: CGFloat = 2

let img = NSImage(size: NSSize(width: width, height: height))
img.lockFocus()

bgImage.draw(in: NSRect(x: 0, y: 0, width: width, height: height))

let pestoCenter = CGPoint(x: 170, y: height - 190)
let appsCenter = CGPoint(x: 490, y: height - 190)
let iconSize: CGFloat = 128
let pestoRect = NSRect(
    x: pestoCenter.x - iconSize / 2,
    y: pestoCenter.y - iconSize / 2,
    width: iconSize,
    height: iconSize
)
let appsRect = NSRect(x: appsCenter.x - iconSize / 2, y: appsCenter.y - iconSize / 2, width: iconSize, height: iconSize)

basilIcon.draw(in: pestoRect)
appsIcon.draw(in: appsRect)

func drawLabel(_ text: String, center: CGPoint) {
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 0.17, green: 0.18, blue: 0.16, alpha: 1.0),
        .paragraphStyle: paragraph
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let size = str.size()
    let textRect = NSRect(
        x: center.x - size.width / 2 - 4,
        y: center.y - iconSize / 2 - size.height - 4,
        width: size.width + 8,
        height: size.height
    )
    str.draw(in: textRect)
}

drawLabel("Pesto", center: pestoCenter)
drawLabel("Applications", center: appsCenter)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else
{
    fatalError("Failed to encode PNG")
}

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : root.appendingPathComponent("docs/images/installer.png").path

try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
