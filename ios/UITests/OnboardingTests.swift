import XCTest

final class OnboardingTests: XCTestCase {
  func testConnectionFormAndSettingsAreAccessible() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.buttons["Connect Life Data"].waitForExistence(timeout: 5))
    app.buttons["Connect Life Data"].tap()
    XCTAssertTrue(app.textFields["Life Data URL"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.secureTextFields["App credential"].exists)
    XCTAssertFalse(app.buttons["Connect"].isEnabled)
    app.textFields["Life Data URL"].tap()
    app.textFields["Life Data URL"].typeText("http://example.invalid")
    app.secureTextFields["App credential"].tap()
    app.secureTextFields["App credential"].typeText("test-value")
    app.buttons["Connect"].tap()
    XCTAssertTrue(
      app.staticTexts["Enter an HTTPS endpoint without credentials, a query or a fragment."]
        .waitForExistence(timeout: 3))
    app.buttons["Cancel"].tap()
    app.buttons["Settings"].tap()
    XCTAssertTrue(app.staticTexts["Reminder time"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Send test notification"].exists)
  }

  func testLocalNotificationAppearsAfterLeavingApp() {
    let app = XCUIApplication()
    app.launch()
    app.buttons["Settings"].tap()
    app.buttons["Send test notification"].tap()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 3) {
      springboard.alerts.buttons["Allow"].tap()
    }
    XCTAssertTrue(
      app.staticTexts[
        "Lock your phone or leave the app. A test notification will arrive in 10 seconds."
      ].waitForExistence(timeout: 5))
    XCUIDevice.shared.press(.home)
    let notification = springboard.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Your phone is ready for birthday reminders.")
    ).firstMatch
    XCTAssertTrue(notification.waitForExistence(timeout: 15))
    let screenshot = XCTAttachment(screenshot: springboard.screenshot())
    screenshot.name = "Background birthday notification"
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
