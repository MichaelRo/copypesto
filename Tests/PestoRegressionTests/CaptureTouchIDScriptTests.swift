// SPDX-License-Identifier: MIT
import Foundation
import Testing

@Suite("Touch ID prompt capture script and lock overlay symbol")
struct CaptureTouchIDScriptTests {
    private struct ScriptResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func runScript(_ arguments: [String]) throws -> ScriptResult {
        let script = root.appendingPathComponent("scripts/capture-touchid-prompt.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ScriptResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    @Test("--help exits 0 and prints usage and options")
    func whenHelpFlagPassed_thenExitsZeroWithUsage() throws {
        let result = try runScript(["--help"])
        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("Usage:"))
        #expect(result.stdout.contains("--output"))
        #expect(result.stdout.contains("--list"))
    }

    @Test("--list runs read-only without error or writing files")
    func whenListFlagPassed_thenRunsSafelyReadOnly() throws {
        let result = try runScript(["--list"])
        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("Pesto") || result.stdout.contains("Touch ID") || result.stdout
            .contains("windows"))
    }

    @Test("BiometricLockOverlay does not hardcode a duplicate touchid SF Symbol above EmbeddedBiometricPrompt")
    func whenInspectingBiometricLockOverlay_thenNoHardcodedDuplicateTouchIDSymbol() throws {
        let overlay = root.appendingPathComponent("Sources/Features/Overlay/BiometricLockOverlay.swift")
        let source = try String(contentsOf: overlay, encoding: .utf8)
        #expect(!source.contains(#"Image(systemName: "touchid")"#))
    }
}
