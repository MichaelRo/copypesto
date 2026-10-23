// SPDX-License-Identifier: MIT
import AppKit

/// The formatted flavours of a text copy (RTF, RTFD and HTML) kept alongside its plain string so a normal paste
/// restores formatting while plain-text paste and search use the plain string.
public struct RichTextPayload: Codable, Equatable, Sendable {
    public var rtf: Data?
    public var rtfd: Data?
    public var html: Data?

    public init(rtf: Data? = nil, rtfd: Data? = nil, html: Data? = nil) {
        self.rtf = rtf
        self.rtfd = rtfd
        self.html = html
    }

    public var isEmpty: Bool {
        rtf == nil && rtfd == nil && html == nil
    }

    /// Writes each stored rich flavour back to `pasteboard`.
    public func write(to pasteboard: NSPasteboard) {
        if let rtfd {
            pasteboard.setData(rtfd, forType: .rtfd)
        }
        if let rtf {
            pasteboard.setData(rtf, forType: .rtf)
        }
        if let html {
            pasteboard.setData(html, forType: .html)
        }
    }
}
