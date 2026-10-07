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
    app.buttons["Add sort rule"].tap()
    app.buttons["Notifications"].tap()
    XCTAssertTrue(app.buttons["sort-direction-notifications"].exists)
    app.buttons["Add sort rule"].tap()
    app.buttons["Name"].tap()
    XCTAssertTrue(app.buttons["sort-direction-name"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Combined sort rules"; screenshot.lifetime = .keepAlways; add(screenshot)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.switches["opt-in-fixture-a"].exists)
  }
  func testSharedToggleSavesAndRefreshPreservesIt() {
    let toggle = app.switches["opt-in-fixture-a"]
    XCTAssertEqual(toggle.value as? String, "0")
    toggle.tap()
    expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
    waitForExpectations(timeout: 5)
    app.swipeDown()
    XCTAssertEqual(toggle.value as? String, "1")
    XCTAssertFalse(app.staticTexts["connection-error"].exists)
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "Confirmed shared notification opt-in"; screenshot.lifetime = .keepAlways; add(screenshot)
  }
}
