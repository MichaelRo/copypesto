// SPDX-License-Identifier: MIT
import Foundation
import Testing

/// `scripts/verify.sh` once printed a green summary over skipped tests and a count that was only one of two lines.
/// `scripts/verify_judge.py` now decides, and these tests feed it fixtures.
@Suite("verify.sh judge")
struct VerifyJudgeScriptTests {
    private func run(_ kind: String, input: String, extra: [String] = []) throws -> (code: Int32, output: String) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("judge-\(UUID().uuidString)")
        try input.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", SourceTree.repositoryRoot.appendingPathComponent("scripts/verify_judge.py").path, kind, file.path
        ] + extra
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }

    private func coreLog(swiftTesting: Int, firstRun: Int = 44, xctest: Int = 38, extra: String = "") -> String {
        """
        \t Executed \(xctest) tests, with 0 failures (0 unexpected) in 0.016 (0.018) seconds
        ✔ Test run with \(firstRun) tests in 20 suites passed after 0.072 seconds.
        \(extra)
        ✔ Test run with \(swiftTesting) tests in 132 suites passed after 1.420 seconds.
        """
    }

    private func hostedTree(passed: Int, ui: Int = 0, snapshots: Int = 0, skipped: [String] = []) throws -> String {
        func cases(_ count: Int, _ prefix: String, _ result: String) -> [[String: Any]] {
            (0..<count).map { [
                "nodeType": "Test Case",
                "name": "t\($0)",
                "nodeIdentifier": "\(prefix)/t\($0)",
                "result": result
            ] }
        }
        var bundles: [[String: Any]] = [[
            "nodeType": "Unit test bundle", "name": "PestoTests", "children": cases(passed, "Suite", "Passed")
                + skipped.map { ["nodeType": "Test Case", "name": $0, "nodeIdentifier": $0, "result": "Skipped"] }
        ]]
        if ui > 0 {
            bundles.append([
                "nodeType": "UI test bundle",
                "name": "PestoUITests",
                "children": cases(ui, "UI", "Passed")
            ])
        }
        if snapshots > 0 {
            bundles.append([
                "nodeType": "Unit test bundle",
                "name": "PestoSnapshotTests",
                "children": cases(snapshots, "Snap", "Passed")
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: ["testNodes": bundles])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("a full Core run passes and the summary names every run")
    func fullCoreRunPasses() throws {
        let result = try run("core", input: coreLog(swiftTesting: 985))
        #expect(result.code == 0, "\(result.output)")
        #expect(result.output.contains("985 Swift Testing + 38 XCTest"))
        #expect(result.output.contains("44+985"))
    }

    @Test("a Core run that ran far fewer tests than expected fails")
    func shortCoreRunFails() throws {
        let result = try run("core", input: coreLog(swiftTesting: 12, firstRun: 5))
        #expect(result.code == 1)
        #expect(result.output.contains("only 12 Swift Testing tests ran"))
    }

    @Test("a Core test that skipped without being listed fails the run; a listed one does not")
    func unexpectedCoreSkipFails() throws {
        let unexpected = try run(
            "core", input: coreLog(swiftTesting: 985, extra: #"◇ Test "the vault opens" skipped: no key"#)
        )
        #expect(unexpected.code == 1)
        #expect(unexpected.output.contains("unexpected skip: the vault opens"))
        let listed = try run(
            "core",
            input: coreLog(swiftTesting: 985, extra: #"◇ Test "the real on-device model describes a picture" skipped"#)
        )
        #expect(listed.code == 0, "\(listed.output)")
    }

    @Test("hosted tests below the floor fail, and a skip that is not listed fails")
    func hostedFloorAndSkips() throws {
        let few = try run("hosted", input: hostedTree(passed: 10), extra: ["--no-ui"])
        #expect(few.code == 1)
        #expect(few.output.contains("only 10 hosted tests passed"))

        let skipped = try run(
            "hosted", input: hostedTree(passed: 300, skipped: ["SettingsFlowTests/test_settings_opensInFront()"]),
            extra: ["--no-ui"]
        )
        #expect(skipped.code == 1)
        #expect(skipped.output.contains("unexpected skip: SettingsFlowTests"))

        let fine = try run("hosted", input: hostedTree(passed: 300), extra: ["--no-ui"])
        #expect(fine.code == 0, "\(fine.output)")
    }

    @Test("a UI run needs its own floor")
    func uiFloor() throws {
        let result = try run("hosted", input: hostedTree(passed: 300, ui: 5))
        #expect(result.code == 1)
        #expect(result.output.contains("only 5 UI tests passed"))
    }

    @Test(
        "when the snapshots are meant to run, too few passing ones fail the run; without the flag they are not judged"
    )
    func snapshotFloor() throws {
        let missing = try run("hosted", input: hostedTree(passed: 300), extra: ["--no-ui", "--snapshots"])
        #expect(missing.code == 1)
        #expect(missing.output.contains("only 0 snapshot tests passed"))

        let ran = try run("hosted", input: hostedTree(passed: 300, snapshots: 32), extra: ["--no-ui", "--snapshots"])
        #expect(ran.code == 0, "\(ran.output)")
        #expect(ran.output.contains("snapshots=32"))

        let notJudged = try run("hosted", input: hostedTree(passed: 300), extra: ["--no-ui"])
        #expect(notJudged.code == 0, "\(notJudged.output)")
    }

    // MARK: The iPhone and iPad runs

    private func mobileTree(unit: Int, uiPassed: [String] = [], uiSkipped: [String] = []) throws -> String {
        func cases(_ names: [String], _ result: String) -> [[String: Any]] {
            names.map { ["nodeType": "Test Case", "name": $0, "nodeIdentifier": "UI/\($0)", "result": result] }
        }
        let bundles: [[String: Any]] = [
            ["nodeType": "Unit test bundle", "name": "PestoMobileTests", "children": (0..<unit).map {
                ["nodeType": "Test Case", "name": "u\($0)", "nodeIdentifier": "Unit/u\($0)", "result": "Passed"]
            }],
            [
                "nodeType": "UI test bundle",
                "name": "PestoMobileUITests",
                "children": cases(uiPassed, "Passed") + cases(uiSkipped, "Skipped")
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["testNodes": bundles])
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func runMobile(phone: String, pad: String, extra: [String] = []) throws -> (code: Int32, output: String) {
        let padFile = FileManager.default.temporaryDirectory.appendingPathComponent("judge-pad-\(UUID().uuidString)")
        try pad.write(to: padFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: padFile) }
        return try run("mobile", input: phone, extra: [padFile.path] + extra)
    }

    private var everyUITest: [String] {
        (0..<20).map { "shared\($0)" }
    }

    @Test("a UI test skipped on one device passes when it passed on the other")
    func deviceOnlyUITestsPass() throws {
        let phone = try mobileTree(unit: 427, uiPassed: everyUITest + ["phoneOnly"], uiSkipped: ["padOnly"])
        let pad = try mobileTree(unit: 427, uiPassed: everyUITest + ["padOnly"], uiSkipped: ["phoneOnly"])
        let result = try runMobile(phone: phone, pad: pad)
        #expect(result.code == 0, "\(result.output)")
        #expect(result.output.contains("iPhone unit=427 iPad unit=427 ui=22"))
    }

    @Test("a UI test skipped on both devices fails the run")
    func skippedEverywhereFails() throws {
        let phone = try mobileTree(unit: 427, uiPassed: everyUITest, uiSkipped: ["neverRan"])
        let pad = try mobileTree(unit: 427, uiPassed: everyUITest, uiSkipped: ["neverRan"])
        let result = try runMobile(phone: phone, pad: pad)
        #expect(result.code == 1)
        #expect(result.output.contains("unexpected skip: UI/neverRan"))
    }

    @Test("each device's unit tests have their own floor, and the UI floor counts what passed on either device")
    func mobileFloors() throws {
        let short = try runMobile(
            phone: mobileTree(unit: 427, uiPassed: everyUITest), pad: mobileTree(unit: 12, uiPassed: everyUITest)
        )
        #expect(short.code == 1)
        #expect(short.output.contains("only 12 iPad unit tests passed"))

        let noUI = try runMobile(phone: mobileTree(unit: 427), pad: mobileTree(unit: 427))
        #expect(noUI.code == 1)
        #expect(noUI.output.contains("only 0 iOS UI tests passed"))

        let unitOnly = try runMobile(phone: mobileTree(unit: 427), pad: mobileTree(unit: 427), extra: ["--no-ui"])
        #expect(unitOnly.code == 0, "\(unitOnly.output)")
    }

    @Test("CI runs the iPhone's unit tests only: with --phone-only the iPad is not judged, without it the run fails")
    func phoneOnlyRun() throws {
        let phone = try mobileTree(unit: 427)
        let ciRun = try runMobile(phone: phone, pad: "{}", extra: ["--no-ui", "--phone-only"])
        #expect(ciRun.code == 0, "\(ciRun.output)")
        #expect(ciRun.output.contains("iPhone unit=427 iPad not run"))

        let gateRun = try runMobile(phone: phone, pad: "{}", extra: ["--no-ui"])
        #expect(gateRun.code == 1)
        #expect(gateRun.output.contains("only 0 iPad unit tests passed"))
    }

    @Test("local gate can run UI only on iPad: --pad-ui-only waives the iPad unit floor without dropping UI checks")
    func padUIOnlyRun() throws {
        let phone = try mobileTree(unit: 427, uiPassed: everyUITest + ["phoneOnly"], uiSkipped: ["padOnly"])
        let pad = try mobileTree(unit: 0, uiPassed: everyUITest + ["padOnly"], uiSkipped: ["phoneOnly"])
        let pass = try runMobile(phone: phone, pad: pad, extra: ["--pad-ui-only"])
        #expect(pass.code == 0, "\(pass.output)")
        #expect(pass.output.contains("iPhone unit=427 iPad ui-only ui=22"))

        let strict = try runMobile(phone: phone, pad: pad)
        #expect(strict.code == 1)
        #expect(strict.output.contains("only 0 iPad unit tests passed"))
    }
}
