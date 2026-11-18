// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

/// The share extension's principal class (`NSExtensionPrincipalClass`): it hosts the SwiftUI sheet and hands the
/// shared attachments to the model.
final class ShareViewController: UIViewController {
    private lazy var model = ShareModel { [weak self] saved in
        guard let context = self?.extensionContext else { return }
        if saved {
            context.completeRequest(returningItems: nil)
        } else {
            context.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        Task { await model.load(providers) }
    }
}
