// SPDX-License-Identifier: MIT
import Foundation
import UniformTypeIdentifiers

/// The file extension Quick Look needs to pick a viewer for a decrypted clip. A type missing here previews as text.
public enum QuickLookFileExtension {
    private static let byTypeIdentifier: [String: String] = [
        "public.png": "png",
        "public.jpeg": "jpg",
        "public.heic": "heic",
        "public.tiff": "tiff",
        "public.gif": "gif",
        "com.compuserve.gif": "gif",
        "org.webmproject.webp": "webp",
        "public.webp": "webp",
        "com.adobe.pdf": "pdf",
        "public.svg-image": "svg",
        "public.rtf": "rtf",
        "public.html": "html",
        "public.url": "webloc",
        "public.mpeg-4": "mp4",
        "video/mp4": "mp4",
        "com.apple.quicktime-movie": "mov",
        "video/quicktime": "mov",
        "public.mp3": "mp3",
        "audio/mpeg": "mp3",
        "public.audio": "m4a",
        "audio/mp4": "m4a",
        "audio/x-m4a": "m4a"
    ]

    /// The table is first because it names the MIME strings clips are stored with; any other picture, document or
    /// movie type the system knows previews as itself.
    public static func forTypeIdentifier(_ identifier: String) -> String {
        if let known = byTypeIdentifier[identifier] { return known }
        guard let type = UTType(identifier), isViewable(type) else { return "txt" }
        return type.preferredFilenameExtension ?? "txt"
    }

    private static func isViewable(_ type: UTType) -> Bool {
        type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .audiovisualContent)
    }
}
