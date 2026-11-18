// SPDX-License-Identifier: MIT
import Foundation
import Observation
import PestoCore

enum WelcomeStep: Int, CaseIterable {
    case keep = 1
    case choices
    case sync

    var next: WelcomeStep? {
        WelcomeStep(rawValue: rawValue + 1)
    }

    var previous: WelcomeStep? {
        WelcomeStep(rawValue: rawValue - 1)
    }
}

/// Where the welcome is (ADR 0057). Link previews are switched on when the second step appears, with the switch in
/// view, and only where nothing is stored: the first step, or a welcome skipped there, leaves them off.
@MainActor
@Observable
final class WelcomeModel {
    static let stepCount = WelcomeStep.allCases.count

    private(set) var step: WelcomeStep = .keep
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.store) {
        self.defaults = defaults
    }

    func goToNextStep() {
        guard let next = step.next else { return }
        move(to: next)
    }

    func goToPreviousStep() {
        guard let previous = step.previous else { return }
        move(to: previous)
    }

    private func move(to target: WelcomeStep) {
        step = target
        if target == .choices, !defaults.hasValue(for: Setting.linkPreviews) {
            defaults.set(true, for: Setting.linkPreviews)
        }
    }
}
