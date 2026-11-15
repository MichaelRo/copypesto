// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os

/// Empties the shared inbox into the history (ADR 0047): each file is opened with the app's private key and ingested
/// through `StorageService.ingest`, so the size limit, the secret scan, masking, sealing and sync apply as for any
/// copy. A file is removed once ingested, refused or found unreadable; only one the store failed to save is kept for
/// the next activation, until `InboxPolicy.maxAge`. Running it twice ingests nothing twice: an ingested file is gone,
/// and one ingested just before a crash is a duplicate ingest already recognises.
public struct InboxDrain: Sendable {
    public struct Report: Equatable, Sendable {
        public var added = 0
        /// Over the size limit, or refused by ingest.
        public var refused = 0
        /// Would not open: sealed to another key, damaged, too large or too old.
        public var discarded = 0
        /// The store failed to save; kept for next time.
        public var kept = 0

        public init() {}

        public var problems: Int {
            refused + discarded
        }
    }

    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "Inbox")
    private let inbox: SharedInbox
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let clock: @Sendable () -> Date

    public init(
        inbox: SharedInbox, privateKey: Curve25519.KeyAgreement.PrivateKey, clock: @escaping @Sendable () -> Date = {
            .now
        }
    ) {
        self.inbox = inbox
        self.privateKey = privateKey
        self.clock = clock
    }

    public func run(into service: StorageService) async -> Report {
        var report = Report()
        let now = clock()
        for stray in inbox.strayFiles() where now.timeIntervalSince(SharedInbox.created(stray)) > 3600 {
            inbox.remove(stray)
        }
        for url in inbox.pendingFiles() {
            await drain(url, now: now, into: service, report: &report)
        }
        return report
    }

    private func drain(_ url: URL, now: Date, into service: StorageService, report: inout Report) async {
        let item: InboxItem
        do {
            item = try InboxEnvelope.open(inbox.contents(of: url), with: privateKey)
        } catch {
            Self.logger.error("Removed an inbox file that did not open: \(String(describing: error), privacy: .public)")
            inbox.remove(url)
            report.discarded += 1
            return
        }
        do {
            try await service.ingest(Self.capture(of: item, now: now))
            inbox.remove(url)
            report.added += 1
        } catch is ClipSizePolicy.TooLarge {
            inbox.remove(url)
            report.refused += 1
        } catch {
            Self.logger.error("Ingesting a shared clip failed: \(error.localizedDescription, privacy: .public)")
            if now.timeIntervalSince(SharedInbox.created(url)) > InboxPolicy.maxAge {
                inbox.remove(url)
                report.discarded += 1
            } else {
                report.kept += 1
            }
        }
    }

    /// The capture ingest takes. A link is its text, which the classifier files as a link.
    public static func capture(of item: InboxItem, now: Date = .now) -> PasteboardCapture {
        let hash = SHA256.hash(data: item.payload).map { String(format: "%02x", $0) }.joined()
        return PasteboardCapture(
            typeIdentifier: item.typeIdentifier, payload: item.payload, payloadString: item.text,
            timestamp: min(item.createdAt, now), contentHash: hash
        ).with(captureMethod: .share)
    }
}
