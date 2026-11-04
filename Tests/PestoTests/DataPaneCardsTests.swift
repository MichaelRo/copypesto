// SPDX-License-Identifier: MIT
import Testing
@testable import Pesto

@MainActor
struct DataPaneCardsTests {
    @Test("the stat strip has no backup tile; the chips beside the headline already say it")
    func statStrip_hasNoBackupTile() {
        #expect(DataStatStrip.statIDs == ["clips", "disk", "oldest"])
    }

    @Test("the off backup card says the switch opens the set-up sheet")
    func backupSentence_whenOff_saysItAsksFirst() {
        let sentence = DataCardCopy.backupSentence(isConfigured: false)
        #expect(sentence.contains("Turning it on asks for a folder and a way to unlock the file first."))
        #expect(sentence.contains("A backup never changes another Mac."))
    }

    @Test("the on backup card keeps its schedule sentence")
    func backupSentence_whenOn_describesTheSchedule() {
        #expect(DataCardCopy.backupSentence(isConfigured: true).contains("rewritten about an hour"))
    }

    @Test("the sync card leads with the delete consequence and keeps \"not a backup\" in its caption")
    func syncCopy_leadsWithTheConsequence() {
        #expect(DataCardCopy.syncLead == "Deleting a clip on one Mac deletes it on all.")
        #expect(DataCardCopy.syncCaption.contains("not a backup"))
    }

    @Test("the no-backup note shows only when sync is on and the backup is not")
    func noBackupNote_onlyWhenSyncIsOnAndBackupIsOff() {
        #expect(DataCardCopy.showsNoBackupNote(syncOn: true, backupOn: false))
        #expect(!DataCardCopy.showsNoBackupNote(syncOn: true, backupOn: true))
        #expect(!DataCardCopy.showsNoBackupNote(syncOn: false, backupOn: false))
        #expect(!DataCardCopy.showsNoBackupNote(syncOn: false, backupOn: true))
    }

    @Test("the closing note stays as agreed")
    func closingNote_isUnchanged() {
        #expect(DataCardCopy.closingNote ==
            "Nothing leaves this Mac until you set this up. Clips with secrets stay out unless you choose.")
    }
}
