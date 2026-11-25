// SPDX-License-Identifier: MIT
import os
import PestoCore
import UIKit

/// Opens Pesto's own `pesto://` links from the keyboard (ADR 0072). `NSExtensionContext.open` does nothing in a
/// keyboard, so the application is found along the responder chain and asked with the plain `open(_:options:)`, as
/// Apple's DTS sample does (developer forums thread 812091, 2026-01); guideline 4.4.1 lets a keyboard open its own app.
/// On iOS 26 it needs Full Access, so the keyboard offers it only then. It never builds a selector from a string.
@MainActor
enum HostURLOpener {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HostURLOpener")

    /// False when no application was found to ask.
    @discardableResult
    static func open(_ url: URL, from start: UIResponder) -> Bool {
        var responder: UIResponder? = start
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { opened in
                    if !opened { logger.warning("Pesto did not open \(url.absoluteString, privacy: .public)") }
                }
                return true
            }
            responder = current.next
        }
        logger.warning("No application on the responder chain to open \(url.absoluteString, privacy: .public)")
        return false
    }
}
