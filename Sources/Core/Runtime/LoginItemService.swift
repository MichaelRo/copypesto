// SPDX-License-Identifier: MIT
import os
import ServiceManagement

public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    public var isOn: Bool {
        self == .enabled
    }

    /// `.notFound` is what macOS reports for a copy it has not registered yet, so it is off and the person can still
    /// ask: only a refused `register()` says why it cannot be turned on.
    public init(systemStatus: SMAppService.Status) {
        switch systemStatus {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered, .notFound: self = .disabled
        @unknown default: self = .unavailable
        }
    }
}

public struct LoginItemChange: Equatable, Sendable {
    public let status: LoginItemStatus
    public let failure: String?
}

public struct LoginItemRefusal: Error, LocalizedError, Sendable {
    public var errorDescription: String? {
        "macOS only registers an installed copy of Pesto."
    }
}

public protocol LoginItemBackend: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

public struct SystemLoginItemBackend: LoginItemBackend {
    public init() {}

    public var status: LoginItemStatus {
        LoginItemStatus(systemStatus: SMAppService.mainApp.status)
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Stands in for the system backend wherever the user's real login items must not change.
public struct InertLoginItemBackend: LoginItemBackend {
    public init() {}
    public var status: LoginItemStatus {
        .disabled
    }

    public func register() throws {
        throw LoginItemRefusal()
    }

    public func unregister() throws {}
}

public struct LoginItemService: Sendable {
    private static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LoginItem")

    private let backend: any LoginItemBackend

    public init(backend: any LoginItemBackend = LoginItemService.defaultBackend()) {
        self.backend = backend
    }

    public static func defaultBackend() -> any LoginItemBackend {
        LaunchMode.current.usesSystemIntegrations ? SystemLoginItemBackend() : InertLoginItemBackend()
    }

    public var status: LoginItemStatus {
        backend.status
    }

    /// The raw status goes in the log so "the toggle is greyed out" can be diagnosed from a real launch.
    public func logStatus() {
        Self.logger.notice("Login item status: \(String(describing: backend.status), privacy: .public)")
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> LoginItemChange {
        var failure: String?
        if enabled != backend.status.isOn {
            do {
                if enabled { try backend.register() } else { try backend.unregister() }
            } catch {
                failure = error.localizedDescription
                Self.logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return LoginItemChange(status: backend.status, failure: failure)
    }
}
