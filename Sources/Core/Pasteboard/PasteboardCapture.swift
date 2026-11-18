// SPDX-License-Identifier: MIT
import Foundation

/// A captured pasteboard event ready for ingestion. Lightweight; the heavy payload bytes
/// are referenced rather than copied repeatedly.
public struct PasteboardCapture: Sendable {
    public let typeIdentifier: String
    public let payload: Data
    public let payloadString: String?
    public let frontmostBundleID: String?
    public let timestamp: Date
    public let contentHash: String
    /// True when the pasteboard contains `com.apple.is-remote-clipboard`, indicating the item
    /// arrived via Universal Clipboard (iPhone, iPad, or other Apple device).
    public let isRemote: Bool
    /// True for a copy the app marked as concealed that was kept because the person allowed that app. It is stored
    /// hidden (shown only on request) and removed when that allowance ends (ADR 0004).
    public let isConcealed: Bool
    /// When the allowance that let a concealed copy in ends (`distantFuture` for "until Pesto quits"); nil otherwise.
    public let concealedUntil: Date?
    /// For a still picture a browser copied: the address of the GIF it came from, read from the HTML flavour. The
    /// browser puts only the first frame on the pasteboard; this is where the whole GIF can be fetched (ADR 0005).
    public let sourceImageURL: URL?
    /// Formatted flavours (RTF, RTFD, HTML) captured alongside a text copy so formatting survives a normal paste.
    public let richPayload: RichTextPayload?
    /// How the person handed this to Pesto on iOS; sealed with the clip on this device only (ADR 0049).
    public var captureMethod: CaptureMethod?

    /// The Mac app that made the copy. A Universal Clipboard copy comes from another device, so whichever Mac app is in
    /// front says nothing about it.
    public var sourceBundleID: String? {
        isRemote ? nil : frontmostBundleID
    }

    public static let remoteSourceName = "Another device"

    public init(
        typeIdentifier: String,
        payload: Data,
        payloadString: String? = nil,
        frontmostBundleID: String? = nil,
        timestamp: Date = .now,
        contentHash: String,
        isRemote: Bool = false,
        isConcealed: Bool = false,
        concealedUntil: Date? = nil,
        sourceImageURL: URL? = nil,
        richPayload: RichTextPayload? = nil
    ) {
        self.concealedUntil = concealedUntil
        self.sourceImageURL = sourceImageURL
        self.richPayload = richPayload
        self.typeIdentifier = typeIdentifier
        self.payload = payload
        self.payloadString = payloadString
        self.frontmostBundleID = frontmostBundleID
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.isRemote = isRemote
        self.isConcealed = isConcealed
    }

    public func with(captureMethod method: CaptureMethod?) -> PasteboardCapture {
        var copy = self
        copy.captureMethod = method
        return copy
    }

    public func with(timestamp: Date) -> PasteboardCapture {
        var copy = PasteboardCapture(
            typeIdentifier: typeIdentifier,
            payload: payload,
            payloadString: payloadString,
            frontmostBundleID: frontmostBundleID,
            timestamp: timestamp,
            contentHash: contentHash,
            isRemote: isRemote,
            isConcealed: isConcealed,
            concealedUntil: concealedUntil,
            sourceImageURL: sourceImageURL,
            richPayload: richPayload
        )
        copy.captureMethod = captureMethod
        return copy
    }
}
