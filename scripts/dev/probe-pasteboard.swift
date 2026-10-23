// SPDX-License-Identifier: MIT
// Read-only: writes what each copy puts on the pasteboard (the types, their sizes, and whether image bytes are a GIF) to
// a JSON file per copy, so a clip that arrives as a still picture can be traced to what the source app offered.
// It never writes to the pasteboard. It keeps no plain text, nothing from a copy marked concealed, and only the first
// 300 characters of HTML or a URL (the part that names an image's address).
//
//   swift scripts/dev/probe-pasteboard.swift [output-dir]      (stop with Ctrl-C)
import AppKit

let output = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/perf/pasteboard-probe",
    isDirectory: true
)
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let board = NSPasteboard.general
var lastCount = board.changeCount
var number = 0
print("Probing the pasteboard; copy a GIF now. Files go to \(output.path). Ctrl-C to stop.")

func isGIF(_ data: Data) -> Bool {
    data.starts(with: Array("GIF89a".utf8)) || data.starts(with: Array("GIF87a".utf8))
}

func describe() -> [String: Any] {
    let types = board.types ?? []
    let concealed = types.contains { $0.rawValue.contains("ConcealedType") || $0.rawValue == "com.apple.is-sensitive" }
    var entries: [[String: Any]] = []
    for type in types {
        var entry: [String: Any] = ["type": type.rawValue]
        if let data = board.data(forType: type) {
            entry["bytes"] = data.count
            entry["gifBytes"] = isGIF(data)
            let lower = type.rawValue.lowercased()
            if !concealed, lower.contains("html") || lower.contains("url") {
                entry["text"] = String(String(decoding: data.prefix(2000), as: UTF8.self).prefix(300))
            }
        }
        entries.append(entry)
    }
    let frontmost = NSWorkspace.shared.frontmostApplication
    return [
        "frontmost": frontmost?.bundleIdentifier ?? "?", "name": frontmost?.localizedName ?? "?",
        "itemCount": board.pasteboardItems?.count ?? 0, "concealed": concealed, "types": entries
    ]
}

while true {
    if board.changeCount != lastCount {
        lastCount = board.changeCount
        number += 1
        let info = describe()
        let name = (info["frontmost"] as? String ?? "?").replacingOccurrences(of: "/", with: "_")
        let file = output.appendingPathComponent(String(format: "%02d-%@.json", number, name))
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file)
        }
        let kinds = (info["types"] as? [[String: Any]] ?? [])
            .map { "\($0["type"] ?? "?")\(($0["gifBytes"] as? Bool) == true ? "[GIF]" : "")" }
        print("#\(number) \(info["name"] ?? "?"): \(kinds.joined(separator: ", "))")
    }
    Thread.sleep(forTimeInterval: 0.1)
}
