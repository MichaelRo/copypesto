// SPDX-License-Identifier: MIT
import AppKit
import SwiftUI

/// Token-level syntax highlighter for code clipboard items.
///
/// Uses NSMutableAttributedString + NSRegularExpression. Covers the top languages
/// developers copy most often. All colors are NSColor semantic colors so they adapt
/// automatically to light / dark appearance.
enum CodeHighlighter {
    struct HighlightedCode {
        let attributedString: AttributedString
    }

    static func highlight(_ code: String, language: String?) -> HighlightedCode {
        let lang = language?.lowercased()
        let base = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrStr = NSMutableAttributedString(
            string: code,
            attributes: [.font: base, .foregroundColor: NSColor.labelColor]
        )

        for rule in rules(for: lang) {
            apply(rule: rule, to: attrStr)
        }

        let attributed = (try? AttributedString(attrStr, including: \.appKit)) ?? AttributedString(code)
        return HighlightedCode(attributedString: attributed)
    }

    // MARK: - Rule engine

    private struct Rule {
        let pattern: String
        let color: NSColor
        var options: NSRegularExpression.Options = [.dotMatchesLineSeparators]
    }

    private static func apply(rule: Rule, to attrStr: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(
            pattern: rule.pattern, options: rule.options
        ) else { return }
        let range = NSRange(attrStr.string.startIndex..., in: attrStr.string)
        for match in regex.matches(in: attrStr.string, range: range) {
            let groupRange = match.range(at: match.numberOfRanges > 1 ? 1 : 0)
            if groupRange.location != NSNotFound {
                attrStr.addAttribute(.foregroundColor, value: rule.color, range: groupRange)
            }
        }
    }

    // MARK: - Language rule sets

    // swiftlint:disable:next cyclomatic_complexity
    private static func rules(for lang: String?) -> [Rule] {
        var result: [Rule] = commonRules(for: lang)
        switch lang {
        case "swift": result += swiftRules
        case "python": result += pythonRules
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": result += jsRules
        case "go": result += goRules
        case "rust": result += rustRules
        case "sql": result += sqlRules
        case "shell", "bash", "sh", "zsh": result += shellRules
        case "html", "xml": result += htmlRules
        case "css", "scss", "less": result += cssRules
        case "java": result += javaRules
        case "kotlin", "kt": result += kotlinRules
        case "ruby", "rb": result += rubyRules
        case "c", "cpp", "c++", "objc", "objective-c": result += cRules
        default: break
        }
        return result
    }

    // Shared: string/comment/number rules applied first so keywords don't re-color string contents.
    private static func commonRules(for lang: String?) -> [Rule] {
        var result: [Rule] = []
        let noBlockComment = ["python", "shell", "bash", "sh", "zsh", "sql"]
        if let lang, !noBlockComment.contains(lang) {
            result.append(Rule(pattern: #"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor))
        }
        result.append(Rule(pattern: #"(?<!\\)"[^"\\]*(?:\\.[^"\\]*)*""#, color: .systemOrange))
        result.append(Rule(pattern: #"(?<!\\)'[^'\\]*(?:\\.[^'\\]*)*'"#, color: .systemOrange))
        let jsLangs = ["javascript", "typescript", "js", "ts", "jsx", "tsx"]
        if let lang, jsLangs.contains(lang) {
            result.append(Rule(pattern: #"`[^`\\]*(?:\\.[^`\\]*)*`"#, color: .systemOrange))
        }
        result.append(Rule(
            pattern: #"\b(0x[0-9a-fA-F]+|0b[01]+|\d+\.?\d*(?:[eE][+-]?\d+)?)\b"#,
            color: .systemBlue,
            options: []
        ))
        return result
    }

    // MARK: - Per-language rules

    private static let swiftRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(actor|any|as|associatedtype|async|await|break|case|catch|class|continue"#
                + #"|default|defer|deinit|do|else|enum|extension|fallthrough|false|fileprivate"#
                + #"|final|for|func|guard|if|import|in|init|inout|internal|is|lazy|let|nonisolated"#
                + #"|nil|open|operator|override|package|precedencegroup|private|protocol|public"#
                + #"|repeat|rethrows|return|self|Self|some|static|struct|subscript|super|switch"#
                + #"|throw|throws|true|try|typealias|unowned|var|weak|where|while)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(@State|@Binding|@ObservedObject|@EnvironmentObject|@Published"#
                + #"|@MainActor|@Sendable|@discardableResult|@objc|@available|@Model|@Query)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let pythonRules: [Rule] = [
        Rule(pattern: #"#[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(pattern: #"\"\"\"[\s\S]*?\"\"\""#, color: .systemOrange),
        Rule(
            pattern: #"\b(and|as|assert|async|await|break|class|continue|def|del|elif|else"#
                + #"|except|False|finally|for|from|global|if|import|in|is|lambda|None"#
                + #"|nonlocal|not|or|pass|raise|return|True|try|while|with|yield)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(self|cls|print|len|range|type|int|str|float|bool|list|dict|tuple|set)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let jsRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(async|await|break|case|catch|class|const|continue|debugger|default"#
                + #"|delete|do|else|export|extends|false|finally|for|from|function|if|import"#
                + #"|in|instanceof|let|new|null|of|return|static|super|switch|this|throw|true"#
                + #"|try|typeof|undefined|var|void|while|with|yield)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(console|Math|Object|Array|Promise|JSON|Error|Date|Map|Set|Symbol)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let goRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(break|case|chan|const|continue|default|defer|else|fallthrough|for"#
                + #"|func|go|goto|if|import|interface|map|package|range|return|select|struct"#
                + #"|switch|type|var)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(bool|byte|error|float32|float64|int|int8|int16|int32|int64|rune"#
                + #"|string|uint|uint8|uint16|uint32|uint64|uintptr|nil|true|false|iota"#
                + #"|make|len|cap|new|append|copy|close|delete|panic|recover|print|println)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let rustRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(as|async|await|break|const|continue|crate|dyn|else|enum|extern"#
                + #"|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return"#
                + #"|Self|self|static|struct|super|trait|true|type|union|unsafe|use|where|while)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(bool|char|f32|f64|i8|i16|i32|i64|i128|isize|str|u8|u16|u32|u64"#
                + #"|u128|usize|String|Vec|Option|Result|None|Some|Ok|Err|Box|Rc|Arc)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let sqlRules: [Rule] = [
        Rule(pattern: #"--[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(pattern: #"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor),
        Rule(
            pattern: #"\b(ADD|ALL|ALTER|AND|ANY|AS|ASC|BACKUP|BETWEEN|BY|CASE|CHECK|COLUMN"#
                + #"|CONSTRAINT|CREATE|DATABASE|DEFAULT|DELETE|DESC|DISTINCT|DROP|EXEC|EXISTS"#
                + #"|FOREIGN|FROM|FULL|GROUP|HAVING|IN|INDEX|INNER|INSERT|INTO|IS|JOIN|KEY"#
                + #"|LEFT|LIKE|LIMIT|NOT|NULL|ON|OR|ORDER|OUTER|PRIMARY|PROCEDURE|RIGHT"#
                + #"|ROWNUM|SELECT|SET|TABLE|TOP|TRUNCATE|UNION|UNIQUE|UPDATE|VALUES|VIEW"#
                + #"|WHERE|WITH)\b"#,
            color: .systemPurple,
            options: .caseInsensitive
        )
    ]

    private static let shellRules: [Rule] = [
        Rule(pattern: #"#[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(alias|bg|break|builtin|case|cd|command|continue|declare|do|done"#
                + #"|echo|elif|else|enable|esac|eval|exec|exit|export|false|fi|for|function"#
                + #"|if|in|jobs|kill|let|local|printf|read|readonly|return|select|set|shift"#
                + #"|source|test|then|time|trap|true|type|typeset|unset|until|wait|while)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(pattern: #"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"#, color: .systemTeal, options: [])
    ]

    private static let htmlRules: [Rule] = [
        Rule(pattern: #"<!--[\s\S]*?-->"#, color: .secondaryLabelColor),
        Rule(pattern: #"</?\s*[a-zA-Z][a-zA-Z0-9-]*"#, color: .systemPurple, options: []),
        Rule(pattern: #"\s([a-zA-Z-]+=)"#, color: .systemTeal, options: [])
    ]

    private static let cssRules: [Rule] = [
        Rule(pattern: #"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor),
        Rule(pattern: #"[.#][a-zA-Z][a-zA-Z0-9_-]*"#, color: .systemPurple, options: []),
        Rule(
            pattern: #"\b(color|background|margin|padding|font|display|position|width|height"#
                + #"|border|flex|grid|animation|transition|transform|opacity|overflow|content"#
                + #"|cursor|text|align|justify)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let javaRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(abstract|assert|boolean|break|byte|case|catch|char|class|const"#
                + #"|continue|default|do|double|else|enum|extends|final|finally|float|for"#
                + #"|goto|if|implements|import|instanceof|int|interface|long|native|new|null"#
                + #"|package|private|protected|public|return|short|static|super|switch"#
                + #"|synchronized|this|throw|throws|true|false|try|void|volatile|while"#
                + #"|record|sealed|permits|var|yield)\b"#,
            color: .systemPurple,
            options: []
        ),
        Rule(
            pattern: #"\b(String|Object|List|Map|Set|ArrayList|HashMap|Optional|Stream"#
                + #"|System|Math|Exception|Integer|Boolean|Double|Long|Float)\b"#,
            color: .systemTeal,
            options: []
        )
    ]

    private static let kotlinRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(abstract|actual|annotation|as|break|by|catch|class|companion|const"#
                + #"|constructor|continue|crossinline|data|delegate|do|dynamic|else|enum"#
                + #"|expect|external|false|fn|for|fun|if|in|infix|init|inline|inner"#
                + #"|interface|internal|is|it|lateinit|noinline|null|object|open|operator"#
                + #"|out|override|package|private|protected|public|reified|return|sealed"#
                + #"|super|suspend|tailrec|this|throw|true|try|typealias|val|var|vararg"#
                + #"|when|where|while)\b"#,
            color: .systemPurple,
            options: []
        )
    ]

    private static let rubyRules: [Rule] = [
        Rule(pattern: #"#[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(BEGIN|END|alias|and|begin|break|case|class|def|do|else|elsif|end"#
                + #"|ensure|false|for|if|in|module|next|nil|not|or|raise|redo|rescue|retry"#
                + #"|return|self|super|then|true|undef|unless|until|when|while|yield"#
                + #"|puts|print|require|include|extend|attr_reader|attr_writer|attr_accessor)\b"#,
            color: .systemPurple,
            options: []
        )
    ]

    private static let cRules: [Rule] = [
        Rule(pattern: #"//[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(pattern: #"#[a-z]+[^\n]*"#, color: .secondaryLabelColor, options: []),
        Rule(
            pattern: #"\b(auto|break|case|char|const|continue|default|do|double|else|enum"#
                + #"|extern|float|for|goto|if|inline|int|long|register|restrict|return|short"#
                + #"|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile"#
                + #"|while|bool|true|false|nullptr|NULL|class|namespace|new|delete|public"#
                + #"|private|protected|virtual|override|template|typename|operator)\b"#,
            color: .systemPurple,
            options: []
        )
    ]
}
