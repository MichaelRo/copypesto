// SPDX-License-Identifier: MIT
import AuthenticationServices
import os
import PestoCore
import SwiftUI
import UIKit

/// The AutoFill extension's principal class (ADR 0051). It offers text insertion and nothing else: every password,
/// passkey and one-time-code entry point is cancelled. It opens the sealed quick-insert set with the shared key and
/// never the store, the history key or the inbox.
final class AutoFillViewController: ASCredentialProviderViewController {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AutoFill")

    override func prepareInterfaceForUserChoosingTextToInsert() {
        let menu = QuickInsertMenu(set: Self.loadSet())
        let picker = InsertPickerView(
            menu: menu,
            insert: { [weak self] entry in
                self?.extensionContext.completeRequest(withTextToInsert: entry.insertionText(), completionHandler: nil)
            },
            cancel: { [weak self] in self?.cancel(.userCanceled) }
        )
        let host = UIHostingController(rootView: picker)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func prepareCredentialList(for _: [ASCredentialServiceIdentifier]) {
        cancel(.failed)
    }

    override func prepareCredentialList(
        for _: [ASCredentialServiceIdentifier],
        requestParameters _: ASPasskeyCredentialRequestParameters
    ) {
        cancel(.failed)
    }

    override func prepareOneTimeCodeCredentialList(for _: [ASCredentialServiceIdentifier]) {
        cancel(.failed)
    }

    override func provideCredentialWithoutUserInteraction(for _: any ASCredentialRequest) {
        cancel(.credentialIdentityNotFound)
    }

    override func prepareInterfaceToProvideCredential(for _: any ASCredentialRequest) {
        cancel(.credentialIdentityNotFound)
    }

    override func prepareInterface(forPasskeyRegistration _: any ASCredentialRequest) {
        cancel(.failed)
    }

    override func prepareInterfaceForExtensionConfiguration() {
        cancel(.failed)
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: ASExtensionError(code))
    }

    private static func loadSet() -> QuickInsertSet? {
        guard let file = QuickInsertFile.current else { return nil }
        do {
            return try file.openSet(keys: .shared())
        } catch {
            logger.error("The AutoFill set did not open: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
