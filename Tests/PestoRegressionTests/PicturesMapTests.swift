// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Every picture is in docs/pictures.md")
struct PicturesMapTests {
    private let root = SourceTree.repositoryRoot

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func mappedFiles() throws -> Set<String> {
        let map = try read("docs/pictures.md")
        let section = map.components(separatedBy: "## Website").first ?? map
        let names = section.matches(of: /`([a-z0-9-]+\.png)`/).map { String($0.output.1) }
        return Set(names)
    }

    private func imagesNamed(in file: String) throws -> Set<String> {
        let text = try read(file)
        let names = text.matches(of: /images\/([a-z0-9-]+\.png)/).map { String($0.output.1) }
        return Set(names)
    }

    @Test("a README or guide picture is in the map")
    func whenReadmeOrGuideUsesPicture_thenMapNamesIt() throws {
        let mapped = try mappedFiles()
        var used = try imagesNamed(in: "README.md")
        let guide = try SourceTree.files(in: "docs/guide", extensions: ["md"], minimum: 8, under: root)
        for file in guide {
            try used.formUnion(imagesNamed(in: SourceTree.relativePath(file)))
        }
        #expect(used.count > 20, "found too few pictures: \(used.count)")
        #expect(used.subtracting(mapped).isEmpty, "not in docs/pictures.md: \(used.subtracting(mapped).sorted())")
    }

    @Test("a picture in docs/images is in the map, and a mapped picture exists")
    func whenImagesFolderChanges_thenMapAgrees() throws {
        let mapped = try mappedFiles()
        let present = try Set(
            SourceTree.files(in: "docs/images", extensions: ["png"], minimum: 20, under: root)
                .map(\.lastPathComponent)
        )
        #expect(present.subtracting(mapped).isEmpty, "not in docs/pictures.md: \(present.subtracting(mapped).sorted())")
        #expect(mapped.subtracting(present).isEmpty, "mapped but missing: \(mapped.subtracting(present).sorted())")
    }

    @Test("the stamp names an app commit")
    func whenStampRead_thenItIsACommitOrUnrecorded() throws {
        let stamp = try read("docs/images/SOURCE").trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(stamp.wholeMatch(of: /commit ([0-9a-f]{40}( dirty)?|unrecorded)/) != nil, "stamp is \(stamp)")
    }
}
