// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// How long a successful Touch ID or password stays good: the History Lock stays open that long and the protected
/// actions (showing a hidden clip, backups, exporting) do not ask again (ADR 0003). A row of Privacy's History lock
/// section, shown with the lock on or off.
struct AuthenticationGracePicker: View {
    @AppStorage(Setting.authenticationGraceMinutes) private var minutes: Int
    private let lockMethod = LockMethod.current()

    var body: some View {
        Picker("Ask for \(lockMethod.name) again after", selection: $minutes) {
            ForEach(AuthenticationGrace.choices, id: \.self) { choice in
                Text(Self.title(choice)).tag(choice)
            }
        }
        .accessibilityIdentifier(AccessibilityID.settingsChoice("authentication", "grace"))
    }

    static func title(_ minutes: Int) -> String {
        switch minutes {
        case 60: String(localized: "1 hour")
        default: String(localized: "\(minutes) minutes")
        }
    }
}
