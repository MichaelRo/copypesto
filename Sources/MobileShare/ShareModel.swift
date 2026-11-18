// SPDX-License-Identifier: MIT
import Foundation
import Observation
import os
import PestoCore

/// The share sheet's one job: read what was shared, show a line of it, and on Save seal it into the inbox.
@MainActor
@Observable
final class ShareModel {
    enum Phase: Equatable {
        case reading
        case ready(preview: String)
        case saved
        case refused(String)
    }

    private(set) var phase: Phase = .reading
    @ObservationIgnored private var item: InboxItem?
    @ObservationIgnored private let inbox: SharedInbox?
    @ObservationIgnored private let finish: @MainActor (Bool) -> Void
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Share")

    init(inbox: SharedInbox? = SharedInbox.current, finish: @escaping @MainActor (Bool) -> Void) {
        self.inbox = inbox
        self.finish = finish
    }

    func load(_ providers: [NSItemProvider]) async {
        guard let inbox else { return refuse(.unavailable) }
        guard (try? inbox.publishedKey()) != nil else { return refuse(.noKey) }
        do {
            guard let read = try await ShareReader.item(from: providers) else {
                let types = providers.flatMap(\.registeredTypeIdentifiers).joined(separator: ", ")
                Self.logger.error("Nothing Pesto keeps among the shared types: \(types, privacy: .public)")
                return refuse(.unsupported)
            }
            item = read
            phase = .ready(preview: Self.preview(of: read))
        } catch let error as InboxError {
            Self.logger.error("A share was refused: \(String(describing: error), privacy: .public)")
            refuse(error)
        } catch {
            Self.logger.error("Reading a share failed: \(error.localizedDescription, privacy: .public)")
            refuse(.unsupported)
        }
    }

    func save() async {
        guard let inbox, let item else { return }
        do {
            try inbox.deposit(item)
            phase = .saved
            try? await Task.sleep(for: .milliseconds(700))
            finish(true)
        } catch let error as InboxError {
            refuse(error)
        } catch {
            Self.logger.error("Saving a share failed: \(error.localizedDescription, privacy: .public)")
            phase = .refused(String(localized: "Couldn\u{2019}t save to Pesto."))
        }
    }

    func cancel() {
        finish(false)
    }

    private func refuse(_ error: InboxError) {
        phase = .refused(Self.message(for: error))
    }

    static func message(for error: InboxError) -> String {
        switch error {
        case .noKey: String(localized: "Open Pesto once first, then share again.")
        case .unavailable: String(localized: "Pesto can\u{2019}t receive shared content on this device.")
        case .full: String(localized: "Pesto has a lot waiting to be added. Open Pesto, then share again.")
        case .tooLarge: String(localized: "This is too large to save from the share sheet.")
        case .unsupported, .wrongKey, .damaged: String(localized: "Pesto can\u{2019}t keep this kind of content.")
        }
    }

    static func preview(of item: InboxItem) -> String {
        guard let text = item.text else { return String(localized: "Picture") }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.trimmingCharacters(in: .whitespaces).prefix(120))
    }
}
