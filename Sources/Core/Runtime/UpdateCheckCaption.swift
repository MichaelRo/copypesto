// SPDX-License-Identifier: MIT
import Foundation

public enum UpdateCheckCaption {
    public static func text(lastCheck: Date?, now: Date = Date(), locale: Locale = .current) -> String {
        guard let lastCheck else { return String(localized: "Not checked yet.") }
        if now.timeIntervalSince(lastCheck) < 60 { return String(localized: "Last checked just now.") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: lastCheck, relativeTo: now)
        return String(localized: "Last checked \(relative).")
    }
}
