// SPDX-License-Identifier: MIT
public enum DragTypes {
    public static let textIdentifiers = ["public.utf8-plain-text", "public.plain-text"]
    public static let filenamesPboardType = "NSFilenamesPboardType"

    private static let png = "public.png"
    private static let gif = "com.compuserve.gif"
    public static let svg = "public.svg-image"
    private static let directImageTypes: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif", svg
    ]

    /// The stored type first, so the receiver gets the original bytes; PNG after it as a universal fallback.
    /// Bytes are never labelled with a type they are not in.
    public static func imageIdentifiers(storedUTI: String) -> [String] {
        let stored = storedUTI == "public.gif" ? gif : storedUTI
        guard directImageTypes.contains(stored) else { return [png] }
        return stored == png ? [png] : [stored, png]
    }
}
