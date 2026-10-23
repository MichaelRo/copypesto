// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("PasteRecorder")
struct PasteRecorderTests {
    private func makeRecorder() -> (PasteRecorder, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pesto-recorder-\(UUID().uuidString)", isDirectory: true)
        return (PasteRecorder(directory: directory), directory)
    }

    @Test("a fresh recorder has no entries")
    func whenNothingRecorded_thenEmpty() {
        let (recorder, directory) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(recorder.entries().isEmpty)
    }

    @Test("a text paste is recorded with its payload")
    func whenTextRecorded_thenEntryHasText() {
        let (recorder, directory) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: directory) }

        recorder.record(.text("hello world"))

        #expect(recorder.entries().map(\.kind) == ["text"])
        #expect(recorder.entries().map(\.text) == ["hello world"])
    }

    @Test("a non-text paste is recorded without a payload")
    func whenNonTextRecorded_thenEntryHasNoText() {
        let (recorder, directory) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: directory) }

        recorder.record(.nonText)

        #expect(recorder.entries().map(\.kind) == ["nonText"])
        #expect(recorder.entries().first?.text == nil)
    }

    @Test("pastes are kept in the order they happened")
    func whenSeveralRecorded_thenOrdered() {
        let (recorder, directory) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: directory) }

        recorder.record(.text("first"))
        recorder.record(.text("second"))
        recorder.record(.nonText)

        #expect(recorder.entries().map(\.kind) == ["text", "text", "nonText"])
        #expect(recorder.entries().compactMap(\.text) == ["first", "second"])
    }

    @Test("text containing newlines and quotes survives the round trip")
    func whenAwkwardText_thenRoundTrips() {
        let (recorder, directory) = makeRecorder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "line one\n\"quoted\" \\ back\tslash"

        recorder.record(.text(text))

        #expect(recorder.entries().first?.text == text)
    }

    @Test("only a uiTest launch has a recorder")
    func recorderExistsOnlyUnderUITest() {
        let base = RuntimeConfiguration(mode: .normal, session: "s", seed: .basic, accessibility: .trusted)
        var uiTest = base
        uiTest.mode = .uiTest
        #expect(PasteRecorder.make(for: base, temporary: URL(fileURLWithPath: "/tmp")) == nil)
        #expect(PasteRecorder.make(for: uiTest, temporary: URL(fileURLWithPath: "/tmp")) != nil)
    }

    @Test("a launch that pastes for real records nothing")
    func whenRealPaste_thenNoRecorder() {
        var config = RuntimeConfiguration(
            mode: .uiTest,
            session: "tests-recorder",
            seed: .basic,
            accessibility: .trusted
        )
        #expect(PasteRecorder.make(for: config, temporary: FileManager.default.temporaryDirectory) != nil)
        config.usesRealPasteboard = true
        #expect(PasteRecorder.make(for: config, temporary: FileManager.default.temporaryDirectory) == nil)
    }
}
