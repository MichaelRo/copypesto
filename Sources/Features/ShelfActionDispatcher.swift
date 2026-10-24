// SPDX-License-Identifier: MIT
import Foundation
import PestoCore
import SwiftUI

/// Dispatcher for view-triggered actions, decoupling SwiftUI views from the concrete application controller.
///
/// Views read this from `@Environment(\.shelfActions)` and execute closures.
/// In production, `AppState` populates these actions. In previews or tests, default no-ops or spies are injected.
public struct ShelfActionDispatcher: Sendable {
    public var writeItem: @MainActor (ClipboardItem) -> PasteCoordinator.PayloadKind?
    public var writeText: @MainActor (String, Bool) -> Void
    public var authenticateInShelf: @MainActor (String, any UserAuthenticating, Bool, AuthenticationGrace) async -> Bool
    public var performBiometricUnlock: @MainActor () async -> Void
    public var finishShelfAuthentication: @MainActor (Bool) -> Void
    public var checkForUpdates: (@MainActor () -> Void)?
    public var showWelcome: (@MainActor () -> Void)?
    public var refreshAuthentication: @MainActor () async -> Void

    public init(
        writeItem: @escaping @MainActor (ClipboardItem) -> PasteCoordinator.PayloadKind? = { _ in nil },
        writeText: @escaping @MainActor (String, Bool) -> Void = { _, _ in },
        authenticateInShelf: @escaping @MainActor (String, any UserAuthenticating, Bool, AuthenticationGrace) async
            -> Bool = { _, _, _, _ in false },
        performBiometricUnlock: @escaping @MainActor () async -> Void = {},
        finishShelfAuthentication: @escaping @MainActor (Bool) -> Void = { _ in },
        checkForUpdates: (@MainActor () -> Void)? = nil,
        showWelcome: (@MainActor () -> Void)? = nil,
        refreshAuthentication: @escaping @MainActor () async -> Void = {}
    ) {
        self.writeItem = writeItem
        self.writeText = writeText
        self.authenticateInShelf = authenticateInShelf
        self.performBiometricUnlock = performBiometricUnlock
        self.finishShelfAuthentication = finishShelfAuthentication
        self.checkForUpdates = checkForUpdates
        self.showWelcome = showWelcome
        self.refreshAuthentication = refreshAuthentication
    }
}

public extension ShelfActionDispatcher {
    @MainActor
    func authenticateInShelf(
        reason: String,
        authenticator: any UserAuthenticating = UserAuthenticator.current,
        embeddedAvailable: Bool? = nil,
        grace: AuthenticationGrace = .shared
    ) async
    -> Bool {
        await authenticateInShelf(
            reason,
            authenticator,
            embeddedAvailable ?? AppState.embeddedBiometricsAvailable,
            grace
        )
    }
}

public extension EnvironmentValues {
    @Entry var shelfActions: ShelfActionDispatcher = .init()
}
