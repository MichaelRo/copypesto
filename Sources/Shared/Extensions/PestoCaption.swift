// SPDX-License-Identifier: MIT
import SwiftUI

extension View {
    /// Explanatory text under a control. `.secondary` measured too faint on a light grouped row for the accessibility
    /// audit's small-text contrast; 70% of the primary colour keeps the quiet look and passes it.
    func pestoCaption() -> some View {
        font(.caption).foregroundStyle(.primary.opacity(0.7))
    }
}
