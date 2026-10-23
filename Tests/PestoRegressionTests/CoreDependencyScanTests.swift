// SPDX-License-Identifier: MIT
import Testing

@Suite("The scan behind CoreDirectoryCycleTests")
struct CoreDependencyScanTests {
    private func edges(_ sources: [(String, String)]) -> Set<String> {
        CoreDependencyScan.edges(sources.map { CoreDependencyScan.Source(folder: $0.0, text: $0.1) })
    }

    @Test("naming a type declared in another folder is an edge")
    func whenATypeIsNamed_thenAnEdge() {
        let found = edges([
            ("Storage", "public struct StorageService {}"),
            ("Paste", "let service: StorageService? = nil")
        ])

        #expect(found == ["Paste->Storage"])
    }

    @Test("a word inside a string literal is not a reference")
    func whenOnlyAStringNamesIt_thenNoEdge() {
        let found = edges([
            ("Paste", "public struct Preview {}"),
            ("Storage", #"let name = "Preview encryption""#),
            ("Search", "let text = \"\"\"\nPreview of the clip\n\"\"\"")
        ])

        #expect(found.isEmpty)
    }

    @Test("a type in a string interpolation is a reference")
    func whenInterpolated_thenAnEdge() {
        let found = edges([
            ("Runtime", "public enum AppIdentity {}"),
            ("Storage", #"let label = "\(AppIdentity.name) store""#)
        ])

        #expect(found == ["Storage->Runtime"])
    }

    @Test("a word in a comment is not a reference")
    func whenOnlyACommentNamesIt_thenNoEdge() {
        let found = edges([
            ("Storage", "public final class StorageService {}"),
            ("Paste", "// asks StorageService to save\nlet x = 1")
        ])

        #expect(found.isEmpty)
    }

    @Test("a nested type does not make its folder the home of a common word")
    func whenNested_thenNotAHome() {
        let found = edges([
            ("Paste", "public struct Coordinator {\n    public enum Failure {}\n}"),
            ("Storage", "let error: Failure? = nil")
        ])

        #expect(found.isEmpty)
    }

    @Test("a name declared in two folders is ambiguous and makes no edge")
    func whenDeclaredTwice_thenAmbiguous() {
        let found = edges([
            ("Paste", "public struct Presentation {}"),
            ("AI", "public struct Presentation {}"),
            ("Storage", "let p: Presentation? = nil")
        ])

        #expect(found.isEmpty)
    }

    @Test("a cycle of any length is found with its path")
    func whenEdgesLoop_thenThePathIsReported() {
        #expect(CoreDependencyScan.cycle(in: ["A->B", "B->C", "C->A"]) == ["A", "B", "C", "A"])
        #expect(CoreDependencyScan.cycle(in: ["A->B", "B->A"]) == ["A", "B", "A"])
    }

    @Test("edges that only go one way have no cycle")
    func whenEdgesAreAcyclic_thenNoCycle() {
        #expect(CoreDependencyScan.cycle(in: ["A->B", "A->C", "B->C"]) == nil)
        #expect(CoreDependencyScan.cycle(in: []) == nil)
    }
}
