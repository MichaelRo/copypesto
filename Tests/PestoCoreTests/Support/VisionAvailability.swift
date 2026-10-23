// SPDX-License-Identifier: MIT
import Foundation

enum VisionAvailability {
    /// Vision's text recognition never returns on a hosted CI runner (a virtual machine without the hardware the
    /// recognizer needs: `VNRecognizeTextRequest` waits forever on its own queue). Tests that run it need a real Mac.
    static let canRecognizeText = ProcessInfo.processInfo.environment["CI"] == nil
        && ProcessInfo.processInfo.environment["PESTO_CI"] == nil
}
