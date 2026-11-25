// SPDX-License-Identifier: MIT
import XCTest

final class ThemeSettingsTests: PestoUITestCase {
    private func openAppearance() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10))
        element(AccessibilityID.settingsSidebar("Appearance")).click()
    }

    private func waitUntilSelected(_ element: XCUIElement) {
        let deadline = Date().addingTimeInterval(5)
        while !element.isSelected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    func test_appearanceSettings_offerFourThemes_withBasilChosen() {
        openAppearance()

        for name in ["basil", "parmesan", "pineNut", "mortar"] {
            XCTAssertTrue(
                element(AccessibilityID.settingsChoice("theme", name)).waitUntilExists(timeout: 5),
                "no \(name) theme in Appearance"
            )
        }
        XCTAssertTrue(element(AccessibilityID.settingsChoice("theme", "basil")).isSelected)
    }

    func test_choosingATheme_selectsIt() {
        openAppearance()
        let parmesan = element(AccessibilityID.settingsChoice("theme", "parmesan"))
        XCTAssertTrue(parmesan.waitUntilExists(timeout: 5))

        parmesan.click()

        waitUntilSelected(parmesan)
        XCTAssertTrue(parmesan.isSelected)
    }
}

final class ThemeAppearancePaneTests: PestoUITestCase {
    func test_everyTheme_drawsTheAppearancePaneInLightAndDark() {
        for theme in ["basil", "parmesan", "pineNut", "mortar"] {
            for mode in ["light", "dark"] {
                launch(defaults: ["hasOnboarded": "true", "appearanceMode": mode, "appTheme": theme])
                send(.openSettings)
                XCTAssertTrue(settingsWindow.waitUntilExists(timeout: 10), "\(theme) \(mode)")
                element(AccessibilityID.settingsSidebar("Appearance")).click()
                XCTAssertTrue(element(AccessibilityID.settingsChoice("theme", theme)).waitUntilExists(timeout: 5))
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                capture("settings-theme-\(theme)-\(mode)", of: settingsWindow)
                app.terminate()
                let ready = workDirectory.appendingPathComponent(UITestSupport.readyFileName)
                try? FileManager.default.removeItem(at: ready)
            }
        }
    }
}

final class ThemeShelfTests: PestoUITestCase {
    func test_everyTheme_drawsTheShelfInLightAndDark() {
        var isFirst = true
        for theme in ["basil", "parmesan", "pineNut", "mortar"] {
            for mode in ["light", "dark"] {
                launch(
                    seed: isFirst ? "marketing" : "empty",
                    defaults: [
                        "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                        "linkPreviewsEnabled": "false", "appearanceMode": mode, "appTheme": theme
                    ],
                    backdrop: "plain"
                )
                isFirst = false
                showOverlay()
                XCTAssertTrue(cards.firstMatch.waitUntilExists(timeout: 10), "\(theme) \(mode)")
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                capture("shelf-\(theme)-\(mode)")
                app.terminate()
                let ready = workDirectory.appendingPathComponent(UITestSupport.readyFileName)
                try? FileManager.default.removeItem(at: ready)
            }
        }
    }
}
