// SPDX-License-Identifier: MIT
// swiftlint:disable no_print_in_release
import AppKit
import PestoCore

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "copy":
    // Text given as arguments is visible to every process (`ps`), so a secret should come through stdin:
    //   echo "text" | pesto copy
    //   echo "secret" | pesto copy --concealed   (kept off Universal Clipboard; Pesto does not record it)
    let concealed = args.contains("--concealed")
    var text = args.dropFirst().filter { $0 != "--concealed" }.joined(separator: " ")
    if text.isEmpty, isatty(STDIN_FILENO) == 0 {
        text = String(bytes: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .newlines) ?? ""
    }
    guard !text.isEmpty else {
        fputs("Usage: echo <text> | pesto copy [--concealed]   (or: pesto copy [--concealed] <text>)\n", stderr)
        exit(1)
    }
    let pb = NSPasteboard.general
    PasteboardProtection.beginWrite(on: pb, protected: concealed)
    pb.setString(text, forType: .string)
    // Pesto's watcher picks up an ordinary copy automatically when the app is running; a concealed one it drops.
    print(concealed ? "Copied to the clipboard, concealed. Pesto does not keep it." : "Copied to the clipboard.")

case "last":
    // The tool cannot ask for Touch ID, so with the History Lock on it hands out nothing.
    let lockIsOn = UserDefaults(suiteName: AppIdentity.bundleID)?.value(for: Setting.biometricLockEnabled) == true
    if lockIsOn {
        fputs("The history lock is on. Unlock Pesto and use the shelf.\n", stderr)
        exit(1)
    }
    guard let item = LastItemStore.read(lockIsOn: lockIsOn) else {
        fputs("No clipboard history found. Is Pesto running?\n", stderr)
        exit(1)
    }
    if args.contains("--json") {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(item), let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    } else {
        print(item.preview)
    }

case "install":
    let selfPath = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let shared = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    let folder = CLIInstall.linkFolder(
        shared: shared, sharedIsWritable: FileManager.default.isWritableFile(atPath: shared.path),
        home: FileManager.default.homeDirectoryForCurrentUser
    )
    let link = folder.appendingPathComponent("pesto")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard CLIInstall.mayReplace(link) else {
            fputs(
                "\(link.path) exists and is not a link made by Pesto. Remove it yourself if you want to replace it.\n",
                stderr
            )
            exit(1)
        }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try FileManager.default.removeItem(at: link)
        }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: selfPath)
        print("Installed: \(link.path) → \(selfPath.path)")
        if folder != shared {
            print("Add \(folder.path) to your PATH if \"pesto\" is not found: export PATH=\"$HOME/.local/bin:$PATH\"")
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

default:
    let name = args.first.map { "pesto \($0)" } ?? "pesto"
    if args.first != nil {
        fputs("Unknown command: \(name)\n\n", stderr)
    }
    print("""
    pesto — Pesto clipboard manager CLI

    Usage:
      pesto copy <text>     Copy text to the clipboard (Pesto saves it as a clip)
      pesto copy --concealed <text>
                            Copy text that Pesto does not keep (it stays off Universal Clipboard)
      pesto last            Print a preview of the latest clip that holds no secret
                            (nothing while the history lock is on)
      pesto last --json     Print as JSON (includes type, timestamp, sourceApp)
      pesto install         Link pesto into /usr/local/bin, or ~/.local/bin when that cannot be written

    Pesto must be running to save what you copy.
    """)
    if args.first != nil { exit(1) }
}
// swiftlint:enable no_print_in_release
