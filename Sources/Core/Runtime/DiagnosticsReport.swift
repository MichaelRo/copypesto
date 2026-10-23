// SPDX-License-Identifier: MIT
import Foundation

/// The lines About copies for a bug report: versions, the Mac, and which switches are on. It takes plain facts and
/// reads nothing itself, so no clip, title, path or setting value outside this list can end up in it.
public enum DiagnosticsReport {
    public struct Facts {
        public var appVersion: String
        public var build: String
        public var macOS: String
        public var hardware: String
        public var architecture: String
        public var isDevelopmentBuild: Bool
        public var switches: [(name: String, isOn: Bool)]
        /// Zero means forever.
        public var keepsClipsForDays: Int

        public init(
            appVersion: String, build: String, macOS: String, hardware: String, architecture: String,
            isDevelopmentBuild: Bool, switches: [(name: String, isOn: Bool)], keepsClipsForDays: Int
        ) {
            self.appVersion = appVersion
            self.build = build
            self.macOS = macOS
            self.hardware = hardware
            self.architecture = architecture
            self.isDevelopmentBuild = isDevelopmentBuild
            self.switches = switches
            self.keepsClipsForDays = keepsClipsForDays
        }
    }

    public static func text(_ facts: Facts) -> String {
        var lines =
            ["Pesto \(facts.appVersion) (\(facts.build))" + (facts.isDevelopmentBuild ? ", development build" : "")]
        lines.append("macOS: \(facts.macOS)")
        lines.append("Mac: \(facts.hardware) (\(facts.architecture))")
        lines += facts.switches.map { "\($0.name): \($0.isOn ? "on" : "off")" }
        lines.append(
            "Keeps clips for (days): " + (facts.keepsClipsForDays == 0
                ? "forever" : "\(facts.keepsClipsForDays)")
        )
        return lines.joined(separator: "\n")
    }
}
