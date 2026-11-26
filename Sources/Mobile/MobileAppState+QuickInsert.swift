// SPDX-License-Identifier: MIT
import Foundation
import os
import PestoCore
import SwiftData

/// The set AutoFill inserts from (ADR 0051): written a moment after the history changes and when Pesto leaves the
/// foreground, emptied by Clear History, and removed with its key when the setting is off or there is no history.
extension MobileAppState {
    private static let quickInsertLogger = Logger(subsystem: AppIdentity.logSubsystem, category: "QuickInsert")

    func startQuickInsert(container: ModelContainer) {
        Self.migrateQuickInsertSettingsIfNeeded()
        quickInsertObserver = ModelSaveObserver.observeChanges(in: container) { [weak self] _ in
            self?.quickInsertHistoryChanged()
        }
        Task { await writeQuickInsertAsync() }
    }

    static func migrateQuickInsertSettingsIfNeeded(defaults: UserDefaults = AppDefaults.store) {
        guard defaults.object(forKey: Setting.keyboardEnabled.name) == nil,
              defaults.object(forKey: Setting.autoFillEnabled.name) == nil,
              defaults.value(for: Setting.quickInsertEnabled) else { return }
        defaults.set(true, for: Setting.keyboardEnabled)
        defaults.set(true, for: Setting.autoFillEnabled)
    }

    func reconcileKeyboardSize(
        defaults: UserDefaults = AppDefaults.store,
        store: KeyboardSizeStore? = .current
    ) {
        guard !isHistoryLockedNow(),
              let record = store?.load(),
              record.size.rawValue != defaults.value(for: Setting.keyboardSize) else { return }
        if let setStamp = quickInsert?.file.modificationDate, record.updatedAt < setStamp {
            return
        }
        defaults.set(record.size.rawValue, for: Setting.keyboardSize)
        writeQuickInsert()
    }

    func quickInsertHistoryChanged() {
        guard quickInsert?.isEnabled() == true else { return }
        quickInsertRewrite?.cancel()
        quickInsertRewrite = Task { [weak self] in
            try? await Task.sleep(for: QuickInsertPolicy.rewriteDelay)
            guard !Task.isCancelled else { return }
            await self?.writeQuickInsertAsync()
        }
    }

    func quickInsertSettingChanged() {
        if quickInsert?.isEnabled() == true { writeQuickInsert() } else { removeQuickInsert() }
    }

    func writeQuickInsertAsync() async {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        quickInsertGeneration &+= 1
        let expectedGeneration = quickInsertGeneration
        guard let target = quickInsert else { return }
        _ = isHistoryLockedNow()
        if historyLock.holdsOutsideSurfaces, target.isEnabled() { return emptyQuickInsert() }
        guard target.isEnabled(), let container = historyContainer else {
            if target.file.exists { removeQuickInsert() }
            return
        }
        let previous = quickInsertWrites
        let now = clock()
        let expiresAt = historyLock.outsideExpiresAt(at: now)
        let options = target.options()
        let device = CardFootLineView.device
        let peers = peerDeviceNames
        let colors = sourceApps.colorsByBundleID
        let next = Task { [weak self] in
            await previous?.value
            guard let self,
                  self.quickInsertGeneration == expectedGeneration,
                  let currentTarget = quickInsert, currentTarget.isEnabled(),
                  !historyLock.holdsOutsideSurfaces else { return }
            do {
                let set = try await Self.buildQuickInsertSet(
                    container: container, now: now, options: options,
                    origin: QuickInsertOrigin(device: device, peerDeviceNames: peers, catalogColors: colors)
                )
                .withExpiresAt(expiresAt)
                .attachingAppIcons(appIcon)
                guard self.quickInsertGeneration == expectedGeneration,
                      let stillTarget = quickInsert, stillTarget.isEnabled(),
                      !historyLock.holdsOutsideSurfaces else { return }
                try stillTarget.file.write(set, with: stillTarget.keys.loadOrCreate())
            } catch {
                guard self.quickInsertGeneration == expectedGeneration else { return }
                Self.quickInsertLogger
                    .error("The AutoFill set was not written: \(error.localizedDescription, privacy: .public)")
                currentTarget.file.remove()
            }
        }
        quickInsertWrites = next
        await next.value
    }

    @concurrent
    private static func buildQuickInsertSet(
        container: ModelContainer, now: Date, options: QuickInsertSelection.Options, origin: QuickInsertOrigin
    ) async throws
        -> QuickInsertSet
    {
        try QuickInsertSelection.set(
            in: ModelContext(container), now: now, options: options,
            source: {
                CardFootLine.source(
                    CardFootLine.origin(of: $0, peerDeviceNames: origin.peerDeviceNames), device: origin.device
                )
            },
            sourceApp: { sourceAppLook(of: $0, catalogColors: origin.catalogColors) }
        )
    }

    /// What a clip's foot line and glow are read from, handed to the build off the main actor.
    struct QuickInsertOrigin {
        let device: CardFootLine.Device
        let peerDeviceNames: [String: String]
        let catalogColors: [String: String]
    }

    /// A card's app and color outside Pesto, as the library's card draws them (ADR 0068): the clip's own sampled
    /// color, else the one a Mac's catalog gave its app.
    nonisolated static func sourceAppLook(of item: ClipboardItem, catalogColors: [String: String]) -> SourceAppLook {
        let own = item.sourceAppLook
        guard own.colorHex == nil, let bundleID = own.bundleID else { return own }
        return SourceAppLook(bundleID: bundleID, colorHex: catalogColors[bundleID])
    }

    /// An app's icon from the catalog the Macs wrote; an iPhone resolves none of its own.
    func appIcon(_ bundleID: String) -> Data? {
        sourceApps.entry(for: bundleID)?.icon
    }

    /// Writes the set now: the current one with the setting on and a history open, otherwise no file and no key. With
    /// the setting off and no file left, the Keychain is not touched at all.
    func writeQuickInsert() {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        quickInsertGeneration &+= 1
        guard let target = quickInsert else { return }
        if historyLock.holdsOutsideSurfaces, target.isEnabled() { return emptyQuickInsert() }
        guard target.isEnabled(), let container = historyContainer else {
            if target.file.exists { removeQuickInsert() }
            return
        }
        do {
            // A context of its own reads what the store holds now; the main context's copy of a clip the storage
            // actor just edited (made secret, say) is merged only a moment after the save.
            let now = clock()
            let device = CardFootLineView.device
            let peers = peerDeviceNames
            let colors = sourceApps.colorsByBundleID
            let set = try QuickInsertSelection.set(
                in: ModelContext(container), now: now, options: target.options(),
                source: { CardFootLine.source(CardFootLine.origin(of: $0, peerDeviceNames: peers), device: device) },
                sourceApp: { Self.sourceAppLook(of: $0, catalogColors: colors) }
            )
            .withExpiresAt(historyLock.outsideExpiresAt(at: now))
            .attachingAppIcons(appIcon)
            try target.file.write(set, with: target.keys.loadOrCreate())
        } catch {
            Self.quickInsertLogger
                .error("The AutoFill set was not written: \(error.localizedDescription, privacy: .public)")
            // The old set may hold a clip deleted or made secret since; no set is better than that one.
            target.file.remove()
        }
    }

    /// Clear History: nothing it removed may stay insertable, so the set is emptied before anything is chosen again.
    /// When locked, writes a locked set so the keyboard and AutoFill show "Locked" instead of "No clips".
    func emptyQuickInsert() {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        quickInsertGeneration &+= 1
        guard let target = quickInsert, target.isEnabled() else { return }
        do {
            let options = target.options()
            let replacement: QuickInsertSet = historyLock.holdsOutsideSurfaces
                ? .locked(accent: options.accent, keyboardSize: options.keyboardSize)
                : .empty(accent: options.accent, keyboardSize: options.keyboardSize)
            try target.file.write(replacement, with: target.keys.loadOrCreate())
        } catch {
            Self.quickInsertLogger
                .error("The AutoFill set was not emptied: \(error.localizedDescription, privacy: .public)")
            target.file.remove()
        }
    }

    func removeQuickInsert() {
        quickInsertRewrite?.cancel()
        quickInsertRewrite = nil
        quickInsertGeneration &+= 1
        guard let target = quickInsert else { return }
        target.file.remove()
        target.keys.remove()
    }
}
