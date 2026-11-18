// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// Which representation of something handed to Pesto (the Paste button, a drop, the share sheet) is kept. A picture
/// wins over a link and a link over text: Safari offers a copied address as both a URL and its text, and a copied
/// picture often carries a name as text beside it. An animated GIF wins over the still copies an app may register
/// beside it (a PNG or JPEG of its first frame), whatever order they are listed in.
public enum SharedContentChoice: Equatable, Sendable {
    case picture(String)
    case pictureToConvert(String)
    case link
    case text

    public static func choose(typeIdentifiers: [String]) -> SharedContentChoice? {
        let types = typeIdentifiers.compactMap(UTType.init)
        if typeIdentifiers.contains(UTType.gif.identifier) { return .picture(UTType.gif.identifier) }
        if let stored = typeIdentifiers.first(where: InboxPolicy.storedPictureTypes.contains) {
            return .picture(stored)
        }
        if let image = types.first(where: { $0.conforms(to: .image) }) { return .pictureToConvert(image.identifier) }
        if types.contains(where: { $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }) { return .link }
        if types.contains(where: { $0.conforms(to: .plainText) }) { return .text }
        return nil
    }
}
