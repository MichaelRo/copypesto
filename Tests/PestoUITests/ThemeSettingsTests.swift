// SPDX-License-Identifier: MIT
import XCTest

final class ThemeSettingsTests: PestoUITestCase {
    private func openAppearance() {
        launch()
        send(.openSettings)
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10))
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
                element(AccessibilityID.settingsChoice("theme", name)).waitForExistence(timeout: 5),
                "no \(name) theme in Appearance"
            )
        }
        XCTAssertTrue(element(AccessibilityID.settingsChoice("theme", "basil")).isSelected)
    }

    func test_choosingAnIcon_leavesTheThemeAlone() {
        openAppearance()
        let mortarIcon = element(AccessibilityID.settingsChoice("appIcon", "mortar"))
        XCTAssertTrue(mortarIcon.waitForExistence(timeout: 5))

        mortarIcon.click()

        waitUntilSelected(mortarIcon)
        XCTAssertTrue(mortarIcon.isSelected)
        XCTAssertTrue(element(AccessibilityID.settingsChoice("theme", "basil")).isSelected)
    }

    func test_choosingATheme_selectsItAndItsIcon() {
        openAppearance()
        let parmesan = element(AccessibilityID.settingsChoice("theme", "parmesan"))
        XCTAssertTrue(parmesan.waitForExistence(timeout: 5))

        parmesan.click()

        waitUntilSelected(parmesan)
        XCTAssertTrue(parmesan.isSelected)
        let icon = element(AccessibilityID.settingsChoice("appIcon", "parmesan"))
        waitUntilSelected(icon)
        XCTAssertTrue(icon.isSelected, "the theme's icon")
    }
}

final class ThemeAppearancePaneTests: PestoUITestCase {
    func test_everyTheme_drawsTheAppearancePaneInLightAndDark() {
        for theme in ["basil", "parmesan", "pineNut", "mortar"] {
            for mode in ["light", "dark"] {
                launch(defaults: ["hasOnboarded": "true", "appearanceMode": mode, "appTheme": theme])
                send(.openSettings)
                XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "\(theme) \(mode)")
                element(AccessibilityID.settingsSidebar("Appearance")).click()
                XCTAssertTrue(element(AccessibilityID.settingsChoice("theme", theme)).waitForExistence(timeout: 5))
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
        for theme in ["basil", "parmesan", "pineNut", "mortar"] {
            for mode in ["light", "dark"] {
                launch(
                    seed: "marketing",
                    defaults: [
                        "hasOnboarded": "true", "cardSize": "large", "accentColorHex": "brand",
                        "linkPreviewsEnabled": "false", "appearanceMode": mode, "appTheme": theme
                    ],
                    backdrop: "plain"
                )
                showOverlay()
                XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10), "\(theme) \(mode)")
                RunLoop.current.run(until: Date().addingTimeInterval(1))
                capture("shelf-\(theme)-\(mode)")
                app.terminate()
                let ready = workDirectory.appendingPathComponent(UITestSupport.readyFileName)
                try? FileManager.default.removeItem(at: ready)
            }
        }
    }
}
