import XCTest

final class LocalizationUITests: XCTestCase {
    func testLanguageSelectionSurvivesRelaunchInBothDirections() {
        let suite = "inkline.localization.ui.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launchEnvironment["INKLINE_TEST_DEFAULTS"] = suite
        defer { app.terminate(); defaults.removePersistentDomain(forName: suite) }

        app.launch()
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.menuBars.menuBarItems["文件"].exists)
        app.typeKey(",", modifierFlags: .command)
        let chineseSettings = app.windows["设置"]
        XCTAssertTrue(chineseSettings.waitForExistence(timeout: 5))
        let language = chineseSettings.popUpButtons["interfaceLanguage"]
        XCTAssertTrue(language.exists)
        let chineseScreenshot = XCTAttachment(screenshot: chineseSettings.screenshot())
        chineseScreenshot.name = "Chinese settings"
        chineseScreenshot.lifetime = .keepAlways
        add(chineseScreenshot)
        language.click()
        app.menuItems["English"].click()
        XCTAssertTrue(app.menuBars.menuBarItems["文件"].exists)
        app.terminate()

        app.launch()
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.menuBars.menuBarItems["File"].exists)
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Replace All"].waitForExistence(timeout: 5))
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey(",", modifierFlags: .command)
        let englishSettings = app.windows["Settings"]
        XCTAssertTrue(englishSettings.waitForExistence(timeout: 5))
        let englishScreenshot = XCTAttachment(screenshot: englishSettings.screenshot())
        englishScreenshot.name = "English settings"
        englishScreenshot.lifetime = .keepAlways
        add(englishScreenshot)
        englishSettings.popUpButtons["interfaceLanguage"].click()
        app.menuItems["简体中文"].click()
        app.terminate()

        app.launch()
        XCTAssertTrue(app.textViews["editor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.menuBars.menuBarItems["文件"].exists)
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(app.buttons["全部替换"].waitForExistence(timeout: 5))
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(app.buttons["打开"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["取消"].exists)
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(app.buttons["保存"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["取消"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }
}
