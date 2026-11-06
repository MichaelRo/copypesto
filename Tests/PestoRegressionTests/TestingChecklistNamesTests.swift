// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("The checklist names tests that exist")
struct TestingChecklistNamesTests {
    private let root = SourceTree.repositoryRoot

    private static let targetNames: Set<String> = [
        "PestoCoreTests", "PestoRegressionTests", "PestoSnapshotTests", "PestoTests", "PestoUITests"
    ]

    /// The suites and UI-test methods a document cites in backticks: `HoverCardClickTests`, `AppChipHoverTests.hover`,
    /// `NoResultsAdviceUITests.test_tab…`, `test_onboarding_…`. A test target's own name is not a test.
    static func citedTypes(in text: String) -> Set<String> {
        Set(text.matches(of: /`([A-Z][A-Za-z0-9]*Tests)(?:\.[A-Za-z0-9_]+)?`/).map { String($0.output.1) })
            .subtracting(targetNames)
    }

    static func citedMethods(in text: String) -> Set<String> {
        let qualified = text.matches(of: /`[A-Z][A-Za-z0-9]*Tests\.(test_[A-Za-z0-9_]+)`/).map { String($0.output.1) }
        let bare = text.matches(of: /`(test_[A-Za-z0-9_]+)`/).map { String($0.output.1) }
        return Set(qualified + bare)
    }

    /// `struct Name` or `class Name` followed by something that ends a name, so `FooTests` is not found in
    /// `FooTestsHelper`.
    private func defined(_ name: String, in source: String) -> Bool {
        let pattern = "(struct|class) \(NSRegularExpression.escapedPattern(for: name))\\b"
        return source.range(of: pattern, options: .regularExpression) != nil
    }

    private func testsSource() throws -> String {
        let files = try SourceTree.files(in: "Tests", minimum: 300, under: root)
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    @Test("the parser finds suites and methods in a sample")
    func whenSampleCitesNames_thenTheyAreFound() {
        let sample = "Run `HoverCardClickTests` and `AppChipHoverTests.hover`, then `FooUITests.test_a_b` or `test_c`. "
            + "Targets such as `PestoUITests` are not tests."
        #expect(Self.citedTypes(in: sample) == ["HoverCardClickTests", "AppChipHoverTests", "FooUITests"])
        #expect(Self.citedMethods(in: sample) == ["test_a_b", "test_c"])
    }

    @Test("every suite and method docs/testing.md cites is defined in Tests")
    func whenChecklistCitesATest_thenItExists() throws {
        let document = try String(contentsOf: root.appendingPathComponent("docs/testing.md"), encoding: .utf8)
        let source = try testsSource()
        let types = Self.citedTypes(in: document)
        let methods = Self.citedMethods(in: document)
        #expect(types.count >= 15, "found too few cited suites: \(types.count)")
        #expect(methods.count >= 2, "found too few cited methods: \(methods.count)")
        let missingTypes = types.filter { !defined($0, in: source) }
        let missingMethods = methods.filter { !source.contains("func \($0)(") }
        #expect(missingTypes.isEmpty, "docs/testing.md cites suites that do not exist: \(missingTypes.sorted())")
        #expect(missingMethods.isEmpty, "docs/testing.md cites tests that do not exist: \(missingMethods.sorted())")
    }
}
