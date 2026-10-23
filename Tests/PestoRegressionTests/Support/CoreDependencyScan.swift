// SPDX-License-Identifier: MIT
import Foundation

/// Which directory of `PestoCore` names a type that another directory declares. A reference is a capitalized word of
/// six or more letters, outside comments and string literals (an interpolation inside one still counts), that is the
/// name of a top-level type declared in one other directory. A nested type is never a home, and a name declared in
/// two directories is skipped.
enum CoreDependencyScan {
    struct Source {
        let folder: String
        let text: String
    }

    private static let declaration = try? NSRegularExpression(
        pattern: #"^(?:public |internal |private |fileprivate |final |indirect |@\w+(?:\([^)]*\))? )*"#
            + #"(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z][A-Za-z0-9_]*)"#,
        options: .anchorsMatchLines
    )
    private static let identifier = try? NSRegularExpression(pattern: #"\b[A-Z][A-Za-z0-9_]{5,}\b"#)
    private static let multilineString = try? NSRegularExpression(pattern: #""""[\s\S]*?""""#)
    private static let string = try? NSRegularExpression(pattern: #""(?:\\.|[^"\\\n])*""#)
    private static let interpolation = try? NSRegularExpression(pattern: #"\\\(([^)]*)\)"#)
    private static let comment = try? NSRegularExpression(pattern: #"//.*"#)

    static func edges(_ sources: [Source], shared: Set<String> = ["Model"]) -> Set<String> {
        var declaredIn: [String: String] = [:]
        var ambiguous: Set<String> = []
        for source in sources {
            let range = NSRange(source.text.startIndex..., in: source.text)
            for match in declaration?.matches(in: source.text, range: range) ?? [] {
                guard let name = Range(match.range(at: 1), in: source.text).map({ String(source.text[$0]) }) else {
                    continue
                }
                if let existing = declaredIn[name], existing != source.folder { ambiguous.insert(name) }
                declaredIn[name] = source.folder
            }
        }
        var found: Set<String> = []
        for source in sources {
            let code = code(of: source.text)
            for match in identifier?.matches(in: code, range: NSRange(code.startIndex..., in: code)) ?? [] {
                guard let range = Range(match.range, in: code) else { continue }
                let name = String(code[range])
                if let home = declaredIn[name], home != source.folder, !shared.contains(home),
                   !ambiguous.contains(name)
                {
                    found.insert("\(source.folder)->\(home)")
                }
            }
        }
        return found
    }

    /// The first loop among "A->B" edges as a path that starts and ends on the same directory, or nil.
    static func cycle(in edges: Set<String>) -> [String]? {
        var next: [String: [String]] = [:]
        for edge in edges.sorted() {
            let parts = edge.components(separatedBy: "->")
            guard parts.count == 2 else { continue }
            next[parts[0], default: []].append(parts[1])
        }
        var finished: Set<String> = []
        func visit(_ node: String, path: [String]) -> [String]? {
            if let start = path.firstIndex(of: node) { return Array(path[start...]) + [node] }
            if finished.contains(node) { return nil }
            for neighbour in next[node] ?? [] {
                if let loop = visit(neighbour, path: path + [node]) { return loop }
            }
            finished.insert(node)
            return nil
        }
        for node in next.keys.sorted() {
            if let loop = visit(node, path: []) { return loop }
        }
        return nil
    }

    private static func code(of text: String) -> String {
        var result = text
        for expression in [multilineString, string] {
            guard let expression else { continue }
            let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                result.replaceSubrange(range, with: " " + interpolations(in: String(result[range])) + " ")
            }
        }
        return comment?.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result), withTemplate: ""
        ) ?? result
    }

    private static func interpolations(in literal: String) -> String {
        let matches = interpolation?.matches(in: literal, range: NSRange(literal.startIndex..., in: literal)) ?? []
        return matches.compactMap { Range($0.range(at: 1), in: literal).map { String(literal[$0]) } }
            .joined(separator: " ")
    }
}
