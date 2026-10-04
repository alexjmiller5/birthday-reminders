import XCTest

@testable import BirthdayCore

final class BirthdayTests: XCTestCase {
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

  func testLeapDayUsesFebruary28OnlyInNonLeapYearsAndGroupsSameDay() throws {
    let people = [
      BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--02-29", enabled: true),
      BirthdayPerson(id: "p2", name: "<person-2>", birthday: "--02-28", enabled: true),
      BirthdayPerson(id: "p3", name: "<person-3>", birthday: "--02-28", enabled: false),
    ]
    var preferences = ReminderPreferences()
    preferences.timeZoneID = "UTC"
    let plan = try ReminderPlan.make(
      people: people, preferences: preferences, now: date("2027-02-01T00:00:00Z"))
    XCTAssertEqual(plan.reminders.first?.date, date("2027-02-28T09:00:00Z"))
    XCTAssertEqual(plan.reminders.first?.names, ["<person-1>", "<person-2>"])
    XCTAssertEqual(plan.reminders.dropFirst().first?.date, date("2028-02-28T09:00:00Z"))
    XCTAssertEqual(plan.reminders.dropFirst(2).first?.date, date("2028-02-29T09:00:00Z"))
  }

  func testCapacityReportsFirstOmittedDateAndMutesApply() throws {
    let people = (1...20).map {
      BirthdayPerson(
        id: "p\($0)", name: "<person-\($0)>", birthday: String(format: "--01-%02d", $0),
        enabled: true)
    }
    var preferences = ReminderPreferences()
    preferences.timeZoneID = "UTC"
    preferences.mutedIDs = ["p1"]
    let plan = try ReminderPlan.make(
      people: people, preferences: preferences, now: date("2027-01-02T10:00:00Z"), limit: 2)
    XCTAssertEqual(
      plan.reminders.map(\.date), [date("2027-01-03T09:00:00Z"), date("2027-01-04T09:00:00Z")])
    XCTAssertEqual(plan.renewBefore, date("2027-01-05T09:00:00Z"))
    let full = try ReminderPlan.make(
      people: people, preferences: preferences, now: date("2027-01-02T10:00:00Z"))
    XCTAssertEqual(full.reminders.count, 60)
    XCTAssertEqual(Set(full.reminders.map(\.id)).count, 60)
    XCTAssertFalse(full.reminders.flatMap(\.names).contains("<person-1>"))
  }

  func testChosenTimeZoneAndDSTDetermineDelivery() throws {
    var preferences = ReminderPreferences()
    preferences.timeZoneID = "America/New_York"
    let people = [BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--03-15", enabled: true)]
    let plan = try ReminderPlan.make(
      people: people, preferences: preferences, now: date("2027-01-01T00:00:00Z"))
    XCTAssertEqual(plan.reminders.first?.date, date("2027-03-15T13:00:00Z"))
    preferences.hour = 25
    XCTAssertThrowsError(
      try ReminderPlan.make(people: people, preferences: preferences, now: Date()))
  }

  func testUnknownYearAndLeapDayAreValidButImpossibleDatesAreRejected() {
    XCTAssertEqual(BirthdayDate("--02-29")?.month, 2)
    XCTAssertEqual(BirthdayDate("--02-29")?.day, 29)
    XCTAssertNotNil(BirthdayDate("2000-02-29"))
    for bad in [
      "2001-02-29", "--02-30", "--13-01", "--00-12", "2000-2-01", "", "--04-31", "٢٠٠٠-01-01",
    ] {
      XCTAssertNil(BirthdayDate(bad), bad)
    }
  }
}
