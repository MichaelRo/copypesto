// SPDX-License-Identifier: MIT
import Testing
@testable import PestoMobile

@Suite("A detail that is open takes what sync changes, and never overwrites a field the person did not touch")
struct ClipDetailsReconcileTests {
    private func form(title: String? = "Title", note: String? = "Note", tags: [String] = ["a"]) -> ClipDetailsDraft {
        ClipDetailsDraft(title: title, note: note, tags: tags)
    }

    @Test("a field changed by sync shows its new value when the person has not touched or focused it")
    func whenSyncChangesAnUntouchedField_thenTheFormFollows() {
        var draft = form()
        var baseline = form()

        draft.reconcile(stored: form(title: "From sync"), baseline: &baseline, editing: nil)

        #expect(draft.title == "From sync")
        #expect(baseline.title == "From sync")
        #expect(draft.touched(since: baseline).isEmpty)
    }

    @Test("a field being typed in, or already changed by the person, keeps what was typed")
    func whenTheFieldIsEditedOrTouched_thenTheDraftStays() {
        var draft = form()
        var baseline = form()
        draft.title = "Typed"

        draft.reconcile(stored: form(title: "From sync", note: "Synced note"), baseline: &baseline, editing: nil)
        #expect(draft.title == "Typed")
        #expect(draft.note == "Synced note")

        var focused = form()
        var focusedBaseline = form()
        focused.reconcile(stored: form(note: "Synced"), baseline: &focusedBaseline, editing: .note)
        #expect(focused.note == "Note")
    }

    @Test("only the touched fields are saved, so a field changed by sync is not written back")
    func whenSaving_thenOnlyWhatThePersonTouchedIsWritten() {
        var draft = form()
        let baseline = form()
        #expect(draft.touched(since: baseline).isEmpty)

        draft.note = "My note"
        draft.tags = "a,  "
        #expect(draft.touched(since: baseline) == [.note])
    }

    @Test("after a save the saved fields are what the form agrees on, and the others still follow sync")
    func whenSaved_thenTheBaselineMoves() {
        var draft = form()
        var baseline = form()
        draft.title = "Mine"
        let saved = draft.touched(since: baseline)

        baseline.didSave(saved, from: draft)
        draft.reconcile(stored: form(title: "Mine", note: "Later"), baseline: &baseline, editing: nil)

        #expect(draft.title == "Mine")
        #expect(draft.note == "Later")
        #expect(draft.touched(since: baseline).isEmpty)
    }
}
