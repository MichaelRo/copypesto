// SPDX-License-Identifier: MIT
import AppKit

/// Gives a rendered 1024 px app icon a transparent background:
/// `swift design/source/mask-icon.swift <in.png> <out.png>`.
/// qlmanage renders on white; the icon body is the rounded rectangle x 100...924 with a 185 px corner.
let arguments = CommandLine.arguments
guard arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else
{
    FileHandle.standardError.write(Data("usage: mask-icon.swift <in.png> <out.png>\n".utf8))
    exit(1)
}

let size = 1024
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
context.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
context.clip()
context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

guard let masked = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: arguments[2]) as CFURL, "public.png" as CFString, 1, nil
      ) else { exit(1) }
CGImageDestinationAddImage(destination, masked, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
