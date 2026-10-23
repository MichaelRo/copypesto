// SPDX-License-Identifier: MIT
import Testing
@testable import PestoCore

@Suite("What the person chooses when the key to their history is gone")
struct KeyLossChoiceTests {
    @Test("the buttons map in order: Quit, Start With Empty History, Restore from Backup")
    func buttons() {
        #expect(KeyLossChoice(buttonIndex: 0) == .quit)
        #expect(KeyLossChoice(buttonIndex: 1) == .startEmpty)
        #expect(KeyLossChoice(buttonIndex: 2) == .restoreFromBackup)
    }

    @Test("anything unexpected is a Quit, which never touches the history")
    func unknownIsQuit() {
        #expect(KeyLossChoice(buttonIndex: 7) == .quit)
        #expect(KeyLossChoice(buttonIndex: -1) == .quit)
    }

    @Test("only Start With Empty History wipes at once; Restore from Backup wipes nothing until a backup is verified")
    func effects() {
        #expect(!KeyLossChoice.quit.startsOver && !KeyLossChoice.quit.opensRestore)
        #expect(KeyLossChoice.startEmpty.startsOver && !KeyLossChoice.startEmpty.opensRestore)
        #expect(!KeyLossChoice.restoreFromBackup.startsOver && KeyLossChoice.restoreFromBackup.opensRestore)
    }
}
