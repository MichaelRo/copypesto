// SPDX-License-Identifier: MIT
import Foundation
import SwiftData
import Testing
@testable import PestoCore
@testable import PestoMobile

@Suite("Building a smart collection from the rules Core already has")
@MainActor
struct SmartCollectionEditingTests {
    @Test("a rule made for any field is valid as it stands, and a text rule is complete once it has words")
    func whenAFieldIsChosen_thenItsRuleIsValid() throws {
        for field in PredicateRule.Field.allCases {
            let rule = SmartRulesDraft.rule(for: field)
            #expect(rule.field == field)
            try PredicateValidator.validate(rule)
            #expect(SmartRulesDraft.operators(for: field).contains(rule.op))
        }
        var text = SmartRulesDraft.rule(for: .previewText)
        #expect(!SmartRulesDraft.isComplete(text))
        text.value = .string("  ")
        #expect(!SmartRulesDraft.isComplete(text))
        text.value = .string("invoice")
        #expect(SmartRulesDraft.isComplete(text))
        #expect(SmartRulesDraft.isComplete(SmartRulesDraft.rule(for: .isPinned)))
    }

    @Test("a rule that is not valid, an operator the field does not allow, is never complete")
    func whenAnOperatorDoesNotFit_thenTheRuleIsIncomplete() {
        let rule = PredicateRule(field: .type, op: .contains, value: .string("text"))
        #expect(!SmartRulesDraft.isComplete(rule))
        let mismatched = PredicateRule(field: .timestamp, op: .newerThanSeconds, value: .string("day"))
        #expect(!SmartRulesDraft.isComplete(mismatched))
    }

    @Test("the offered operators follow the Core's allowed set, in a fixed order")
    func whenOperatorsAreListed_thenTheyAreCoresAllowedOnes() {
        for field in PredicateRule.Field.allCases {
            #expect(Set(SmartRulesDraft.operators(for: field)) == PredicateValidator.allowedOperators(for: field))
        }
        #expect(SmartRulesDraft.operators(for: .timestamp) == [.newerThanSeconds, .olderThanSeconds])
        #expect(SmartRulesDraft.operators(for: .isRemote) == [.isTrue, .isFalse])
    }

    @Test("an app's bundle id is offered only while a rule already uses it")
    func whenNoRuleUsesTheBundleID_thenItIsNotOffered() {
        #expect(!SmartRulesDraft.starter.fields.contains(.sourceBundleID))
        var draft = SmartRulesDraft.starter
        draft.ruleSet.groups[0].rules.append(PredicateRule(
            field: .sourceBundleID, op: .equals, value: .string("com.apple.Safari")
        ))
        #expect(draft.fields.contains(.sourceBundleID))
        #expect(draft.fields.count == PredicateRule.Field.allCases.count)
    }

    @Test("the words say what a rule means for a pinned and for an other-device rule")
    func whenAnOperatorIsNamed_thenItIsPlainForItsField() {
        #expect(SmartRuleWords.title(of: .isTrue, field: .isPinned) == "is pinned")
        #expect(SmartRuleWords.title(of: .isTrue, field: .isRemote) == "another device")
        #expect(SmartRuleWords.title(of: .isFalse, field: .isRemote) == "this device")
        #expect(SmartRuleWords.title(of: .isRemote) == "Copied on")
        #expect(SmartRuleWords.ageTitle(seconds: 86_400) == "A day")
        #expect(!SmartRuleWords.ageTitle(seconds: 5400).isEmpty)
    }

    @Test("a smart collection is saved with its rules and matches the clips they describe")
    func whenCreatedSmart_thenItsRulesFillIt() async throws {
        let library = try await MobileTestLibrary()
        let note = try await library.add("a plain note")
        try await library.service.ingest(#require(ClipCapture.text("https://copypesto.net/guide")))
        let link = try await library.settle()

        var draft = CollectionDraft.new(existing: [])
        draft.name = "Links"
        draft.isSmart = true
        draft.rules?.ruleSet.groups[0].rules[0] = PredicateRule(field: .type, op: .equals, value: .string("url"))
        #expect(draft.canSave)
        let board = try #require(library.state.addCollection(draft, existing: []))

        #expect(board.isSmart)
        let rules = try #require(SmartRulesDraft(data: board.smartPredicateData))
        #expect(rules.ruleSet.matches(link))
        #expect(!rules.ruleSet.matches(note))
        #expect(library.state.undoHistory?.undoLabel == .createCollection("Links"))
    }

    @Test("an incomplete smart collection cannot be saved, and a plain one always can")
    func whenARuleIsEmpty_thenSavingIsRefused() {
        var draft = CollectionDraft.new(existing: [])
        #expect(draft.canSave)
        draft.isSmart = true
        draft.rules?.ruleSet.groups[0].rules[0] = SmartRulesDraft.rule(for: .previewText)
        #expect(!draft.canSave)
        draft.rules?.ruleSet.groups[0].rules[0].value = .string("basil")
        #expect(draft.canSave)
    }

    @Test("changing the rules is one edit that Undo takes back")
    func whenRulesChange_thenUndoRestoresThem() async throws {
        let library = try await MobileTestLibrary()
        var draft = CollectionDraft.new(existing: [])
        draft.name = "Smart"
        draft.isSmart = true
        let board = try #require(library.state.addCollection(draft, existing: []))
        let before = try #require(board.smartPredicateData)

        var edited = CollectionDraft(board)
        edited.rules?.ruleSet.groups[0].rules[0] = PredicateRule(
            field: .type, op: .notEquals, value: .string("image")
        )
        #expect(edited.differs(from: board))
        library.state.updateCollection(board, to: edited, existing: [board])
        #expect(board.smartPredicateData != before)
        #expect(library.state.undoHistory?.undoLabel == .editCollection("Smart"))

        await library.state.undo()
        try await library.refreshed()
        let container = try #require(library.state.historyContainer)
        let restored = try #require(try ModelContext(container).fetch(FetchDescriptor<Pinboard>()).first)
        #expect(restored.smartPredicateData == before)
    }

    @Test("rules this version cannot read are left alone when the name changes")
    func whenRulesAreFromANewerVersion_thenTheyAreKept() async throws {
        let library = try await MobileTestLibrary()
        var future = SmartRulesDraft.starter.ruleSet
        future.schemaVersion = 9
        let data = try SmartCollectionPredicate.encoder.encode(future)
        let context = try #require(library.state.historyContainer?.mainContext)
        let board = Pinboard(
            name: "From Later",
            symbolName: "folder",
            colorHex: "3DAF60",
            sortOrder: 0,
            isSmart: true,
            smartPredicateData: data
        )
        context.insert(board)
        try context.save()

        var draft = CollectionDraft(board)
        #expect(draft.rules == nil)
        #expect(draft.isSmart && draft.canSave)
        draft.name = "Renamed"
        library.state.updateCollection(board, to: draft, existing: [board])

        #expect(board.name == "Renamed")
        #expect(board.smartPredicateData == data)
    }

    @Test("a plain collection's draft carries the starter rules but never saves them")
    func whenPlain_thenNoRulesAreSaved() async throws {
        let library = try await MobileTestLibrary()
        let board = try #require(library.state.addCollection(named: "Trip", existing: []))
        #expect(!board.isSmart && board.smartPredicateData == nil)
        #expect(!CollectionDraft(board).isSmart)
    }

    @Test("removing a rule removes that rule, wherever it is, and the others keep their ids and their values")
    func whenARuleIsRemoved_thenTheRightOneGoes() {
        var draft = SmartRulesDraft.starter
        let group = draft.groupIDs[0]
        draft.addRule(to: group)
        draft.addRule(to: group)
        let ids = draft.ruleIDs(in: group)
        draft.setRule(ids[0], to: SmartRulesDraft.rule(for: .isPinned))
        draft.setRule(ids[1], to: SmartRulesDraft.rule(for: .previewText))
        draft.setRule(ids[2], to: SmartRulesDraft.rule(for: .tags))

        draft.removeRule(ids[1])
        #expect(draft.ruleIDs(in: group) == [ids[0], ids[2]])
        #expect(draft.rule(ids[0])?.field == .isPinned)
        #expect(draft.rule(ids[2])?.field == .tags)
        #expect(draft.rule(ids[1]) == nil)

        draft.removeRule(ids[2])
        #expect(draft.ruleIDs(in: group) == [ids[0]])
        draft.removeRule(ids[0])
        #expect(draft.ruleIDs(in: group) == [ids[0]], "a group keeps its last rule")
        #expect(draft.ruleSet.groups[0].rules.map(\.field) == [.isPinned])
    }

    @Test("removing a group removes that group and keeps the last one; new groups and rules get ids of their own")
    func whenAGroupIsRemoved_thenTheRightOneGoes() {
        var draft = SmartRulesDraft.starter
        draft.addGroup()
        draft.addGroup()
        let groups = draft.groupIDs
        #expect(Set(groups).count == 3)
        draft.setRule(draft.ruleIDs(in: groups[1])[0], to: SmartRulesDraft.rule(for: .isRemote))
        draft.removeGroup(groups[0])
        #expect(draft.groupIDs == [groups[1], groups[2]])
        #expect(draft.ruleSet.groups[0].rules[0].field == .isRemote)
        draft.removeGroup(groups[2])
        draft.removeGroup(groups[1])
        #expect(draft.groupIDs == [groups[1]])
    }

    @Test("a rule set the editor reads keeps its own shape, including one with no groups")
    func whenThereAreNoGroups_thenTheRulesAreReadable() throws {
        let empty = PredicateRuleSet(combinator: .and, groups: [])
        let data = try SmartCollectionPredicate.encodeRuleSet(empty)
        let draft = try #require(SmartRulesDraft(data: data))
        #expect(draft.groupIDs.isEmpty)
        #expect(draft.isComplete)
    }

    @Test("a rename leaves the stored rules byte for byte as they were, even in an older format")
    func whenOnlyTheNameChanges_thenTheRulesAreNotWrittenAgain() async throws {
        let library = try await MobileTestLibrary()
        let v1 = try SmartCollectionPredicate.encode(PredicateRule(field: .type, op: .equals, value: .string("url")))
        let context = try #require(library.state.historyContainer?.mainContext)
        let board = Pinboard(
            name: "Old", symbolName: "folder", colorHex: "3DAF60", sortOrder: 0, isSmart: true,
            smartPredicateData: v1
        )
        context.insert(board)
        try context.save()

        var draft = CollectionDraft(board)
        #expect(draft.rules != nil)
        draft.name = "Renamed"
        library.state.updateCollection(board, to: draft, existing: [board])

        #expect(board.name == "Renamed")
        #expect(board.smartPredicateData == v1)
    }
}
