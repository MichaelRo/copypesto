// SPDX-License-Identifier: MIT
import Foundation

/// Asks the on-device model for better names for a snippet's fill-ins (ADR 0017, ADR 0005). The model reads the
/// template
/// with numbered blanks, so none of the values the fields stand for goes with it, and it is asked once, on a click.
public enum SnippetNaming {
    public typealias Completion = @Sendable (_ system: String, _ message: String) async throws -> String

    public struct Request: Equatable, Sendable {
        public let system: String
        public let message: String
    }

    public static func request(for template: String) -> Request {
        var blanked = template
        for (offset, field) in FillInParser.fields(in: template).enumerated() where field.kind != .optional {
            blanked = blanked.replacingOccurrences(of: field.token, with: "[\(offset + 1)]")
        }
        return Request(
            system: "You name the blanks of a reusable text template. Reply with one short name per blank, "
                + "in order, one per line, 1 to 3 words each, no numbering, no explanation.",
            message: "Template:\n\(blanked)"
        )
    }

    /// The template with its fields renamed from the model's answer, or nil when the answer is unusable.
    public static func applying(_ answer: String, to template: String) -> String? {
        let fields = FillInParser.fields(in: template).filter { $0.kind != .optional }
        let names = answer.split(whereSeparator: \.isNewline)
            .map { line in
                String(line).replacingOccurrences(of: #"^\s*\d+[.)]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        guard names.count == fields.count, Set(names).count == names.count,
              names.allSatisfy(isUsable) else { return nil }
        var renamed = template
        for (field, name) in zip(fields, names) {
            let replacement = SnippetField(label: name, kind: field.kind, defaultValue: field.defaultValue)
            renamed = renamed.replacingOccurrences(of: field.token, with: replacement.token)
        }
        return renamed
    }

    public static func suggest(for template: String, using complete: Completion) async -> String? {
        let ask = request(for: template)
        guard let answer = try? await complete(ask.system, ask.message) else { return nil }
        return applying(answer, to: template)
    }

    private static func isUsable(_ name: String) -> Bool {
        name.count <= FillInParser.maxLabelLength && !name.contains(where: { "{}\"|".contains($0) })
    }
}
