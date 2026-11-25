// SPDX-License-Identifier: MIT
import os
import PestoCore
import UIKit

/// Opens one of Pesto's own `pesto://` links from an extension. `NSExtensionContext.open` does nothing in a keyboard
/// and is not promised to work in a credential provider, so the application is found along the responder chain and
/// asked through its `openURL:options:completionHandler:` selector; the context's `open` is the fallback.
@MainActor
enum HostURLOpener {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "HostURLOpener")

    /// `contextFirst` (AutoFill) asks the context first and goes through the responder chain only when that opens
    /// nothing, so the chain is used only where the documented way fails.
    static func open(_ url: URL, from start: UIResponder, context: NSExtensionContext?, contextFirst: Bool = false) {
        guard contextFirst, let context else { return openThroughApplication(url, from: start, context: context) }
        Task { @MainActor in
            if await context.open(url) { return }
            openThroughApplication(url, from: start, context: nil)
        }
    }

    private static func openThroughApplication(_ url: URL, from start: UIResponder, context: NSExtensionContext?) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = start
        while let current = responder {
            if current is UIApplication,
               current.responds(to: selector),
               let method = class_getInstanceMethod(type(of: current), selector)
            {
                typealias OpenIMP = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                )
                    -> Void
                let imp = unsafeBitCast(method_getImplementation(method), to: OpenIMP.self)
                imp(current, selector, url as NSURL, [:] as NSDictionary) { opened in
                    guard !opened else { return }
                    logger.warning("UIApplication.open returned false for \(url.absoluteString, privacy: .public)")
                    Task { @MainActor in _ = await context?.open(url) }
                }
                return
            }
            responder = current.next
        }
        Task { _ = await context?.open(url) }
    }
}
