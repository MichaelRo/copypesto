// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PestoCore

@Suite("Text recognition switch")
struct OCRDisabledSwitchTests {
    private static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    @Test("the switch is read from the environment, and only a present value turns recognition off")
    func whenTheVariableIsSet_thenRecognitionIsDisabled() {
        #expect(OCRService.isDisabled(environment: [OCRService.disableVariable: "1"]))
        #expect(!OCRService.isDisabled(environment: [:]))
    }

    @Test("a disabled recognizer reads nothing and does not call Vision")
    func whenDisabled_thenRecognizeReturnsNilAndPrewarmReturns() async {
        let service = OCRService(environment: [OCRService.disableVariable: "1"])

        #expect(await service.recognize(imageData: Self.png) == nil)
        await service.prewarm()
    }
}
