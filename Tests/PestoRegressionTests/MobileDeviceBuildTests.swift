// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `make build-mobile-device` used to embed `$(DEVICE)` inside single quotes, which broke on apostrophes like
/// `Alex's iPhone`. Keeping `DEVICE` and `DEVICE_ID` in environment variables read by `scripts/build-mobile-device.sh`
/// avoids shell quoting altogether.
@Suite("Mobile device build script")
struct MobileDeviceBuildTests {
    private let root = SourceTree.repositoryRoot

    private struct DryRunResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private func runDryRun(env: [String: String]) throws -> DryRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = root
        process.arguments = ["bash", root.appendingPathComponent("scripts/build-mobile-device.sh").path, "--dry-run"]
        var environment = ProcessInfo.processInfo.environment
        for key in ["DEVICE", "DEVICE_ID", "APPLE_TEAM_ID", "MOBILE_SCHEME", "MOBILE_BUILD_DIR"] {
            environment.removeValue(forKey: key)
        }
        for (key, value) in env {
            environment[key] = value
        }
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return DryRunResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    @Test("device names with ASCII or curly apostrophes pass through as a single destination argument")
    func whenDeviceHasApostrophe_thenDestinationIsPreserved() throws {
        for name in ["Alex's iPhone", "Alex’s iPhone"] {
            let result = try runDryRun(env: ["DEVICE": name, "APPLE_TEAM_ID": "TEAM123456"])
            #expect(result.status == 0, "stderr: \(result.stderr)")
            let args = result.stdout.split(separator: "\n").map(String.init)
            #expect(args.contains("platform=iOS,name=\(name)"))
            #expect(args.contains("DEVELOPMENT_TEAM=TEAM123456"))
        }
    }

    @Test("quotes and command-substitution text in DEVICE are never evaluated by a shell")
    func whenDeviceContainsShellMetacharacters_thenPassedLiterally() throws {
        let tricky = #"Pat "Pro" $(whoami) iPhone"#
        let result = try runDryRun(env: ["DEVICE": tricky, "APPLE_TEAM_ID": "TEAM123456"])
        #expect(result.status == 0, "stderr: \(result.stderr)")
        let args = result.stdout.split(separator: "\n").map(String.init)
        #expect(args.contains("platform=iOS,name=\(tricky)"))
    }

    @Test("DEVICE_ID takes precedence and builds an id= destination")
    func whenDeviceIDIsProvided_thenUsesUDIDDestination() throws {
        let result = try runDryRun(env: [
            "DEVICE": "Ignored Name",
            "DEVICE_ID": "00000000-0000000000000000",
            "APPLE_TEAM_ID": "TEAM123456"
        ])
        #expect(result.status == 0, "stderr: \(result.stderr)")
        let args = result.stdout.split(separator: "\n").map(String.init)
        #expect(args.contains("platform=iOS,id=00000000-0000000000000000"))
        #expect(!args.contains(where: { $0.contains("Ignored Name") }))
    }

    @Test("missing device or missing team fails cleanly with guidance")
    func whenRequiredInputsAreMissing_thenFails() throws {
        let noDevice = try runDryRun(env: ["APPLE_TEAM_ID": "TEAM123456"])
        #expect(noDevice.status != 0)
        #expect(noDevice.stderr.contains("DEVICE_ID"))

        let noTeam = try runDryRun(env: ["DEVICE": "Alex's iPhone"])
        #expect(noTeam.status != 0)
        #expect(noTeam.stderr.contains("APPLE_TEAM_ID"))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = root
        process.arguments = [
            "bash",
            root.appendingPathComponent("scripts/build-mobile-device.sh").path,
            "--unexpected"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 2)
    }

    @Test("Makefile delegates build-mobile-device safely via GNU Make CLI and environment")
    func whenInvokedViaMake_thenApostrophesAndMetacharactersHold() throws {
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(!makefile.contains("'platform=iOS,name=$(DEVICE)'"))
        #expect(!makefile.contains("build-mobile-device: export"))
        #expect(makefile.contains("scripts/build-mobile-device.sh"))

        func runMake(_ args: [String], env: [String: String] = [:]) throws -> DryRunResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/make")
            process.currentDirectoryURL = root
            process.arguments = [
                "PESTO_SKIP_GENERATE=1",
                "APPLE_TEAM_ID=TEAM123456",
                "build-mobile-device"
            ] + args
            var environment = ProcessInfo.processInfo.environment
            environment["PESTO_MOBILE_DRY_RUN"] = "1"
            for key in ["DEVICE", "DEVICE_ID"] {
                environment.removeValue(forKey: key)
            }
            for (key, value) in env {
                environment[key] = value
            }
            process.environment = environment
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return DryRunResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        }

        let cliApostrophe = try runMake(["DEVICE=Alex's iPhone"])
        #expect(cliApostrophe.status == 0, "stderr: \(cliApostrophe.stderr)")
        #expect(cliApostrophe.stdout.split(separator: "\n").contains("platform=iOS,name=Alex's iPhone"))

        let envDollar = try runMake([], env: ["DEVICE": #"Pat $(whoami) iPhone"#])
        #expect(envDollar.status == 0, "stderr: \(envDollar.stderr)")
        #expect(envDollar.stdout.split(separator: "\n").contains(#"platform=iOS,name=Pat $(whoami) iPhone"#))

        let cliID = try runMake(["DEVICE_ID=00000000-0000000000000000"])
        #expect(cliID.status == 0, "stderr: \(cliID.stderr)")
        #expect(cliID.stdout.split(separator: "\n").contains("platform=iOS,id=00000000-0000000000000000"))
    }
}
