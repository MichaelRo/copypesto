// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

extension EnvironmentValues {
    /// The shelf's editor for a clip, which a card reads for the edits its popovers make. Nil where there is no shelf
    /// (a preview or a snapshot), and the card saves the edit itself.
    @Entry var clipEditor: ClipEditor?
}
