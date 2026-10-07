import XCTest

final class BirthdayListUITests: XCTestCase {
  private var app: XCUIApplication!
  override func setUp() {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-birthdays-ui-fixture"]
    app.launch()
    XCTAssertTrue(app.switches["opt-in-fixture-a"].waitForExistence(timeout: 5))
  }
  override func tearDown() {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Final list interaction state"; screenshot.lifetime = .keepAlways; add(screenshot)
    if testRun?.hasSucceeded == false { print(app.debugDescription) }
    app.terminate()
    app.launchArguments = ["-birthdays-clear-ui-fixture"]
    app.launch()
    app.terminate()
  }
  func testSearchAndCombinedSortControls() {
    let search = app.searchFields.firstMatch
    if !search.isHittable { app.swipeDown() }
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.tap(); search.typeText("PERSON-A")
    XCTAssertTrue(app.switches["opt-in-fixture-a"].exists)
    XCTAssertFalse(app.switches["opt-in-fixture-b"].exists)
    app.buttons["Cancel"].tap()
    app.buttons["Sort"].tap()
    XCTAssertTrue(app.navigationBars["Sort birthdays"].waitForExistence(timeout: 3))
    app.buttons["sort-direction-birthday"].tap()
    XCTAssertTrue(app.buttons["sort-direction-birthday"].label.contains("Latest first"))
    app.buttons["Add sort rule"].buttons.firstMatch.tap()
    let notifications = app.descendants(matching: .any).matching(identifier: "Notifications").firstMatch
    XCTAssertTrue(notifications.waitForExistence(timeout: 3))
    notifications.tap()
    XCTAssertTrue(app.buttons["sort-direction-notifications"].exists)
    app.buttons["Add sort rule"].buttons.firstMatch.tap()
    app.descendants(matching: .any).matching(identifier: "Name").firstMatch.tap()
    XCTAssertTrue(app.buttons["sort-direction-name"].exists)
    app.buttons["Reorder Name"].press(forDuration: 1, thenDragTo: app.buttons["Reorder Upcoming birthday"])
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Combined sort rules"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.switches["opt-in-fixture-a"].exists)
    XCTAssertLessThan(app.switches["opt-in-fixture-a"].frame.minY, app.switches["opt-in-fixture-b"].frame.minY)
  }
  func testSharedToggleSavesAndRefreshPreservesIt() {
    let toggle = app.switches["opt-in-fixture-a"]
    XCTAssertEqual(toggle.value as? String, "0")
    XCTAssertTrue(toggle.isEnabled)
    XCTAssertTrue(toggle.isHittable)
    toggle.switches.firstMatch.tap()
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
    waitForExpectations(timeout: 5)
    app.swipeDown()
    XCTAssertEqual(toggle.value as? String, "1")
    XCTAssertFalse(app.staticTexts["connection-error"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Confirmed shared notification opt-in"; screenshot.lifetime = .keepAlways; add(screenshot)
    toggle.switches.firstMatch.tap()
    expectation(for: NSPredicate(format: "value == '0'"), evaluatedWith: toggle)
    waitForExpectations(timeout: 5)
  }
}
