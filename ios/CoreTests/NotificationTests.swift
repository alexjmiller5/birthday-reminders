import XCTest

@testable import BirthdaysCore

private actor TestStore: NotificationStore {
  var ids: Set<String> = ["birthday-stale", "test-notification"]
  let fail: Bool
  init(fail: Bool = false) { self.fail = fail }
  func pendingIDs() -> Set<String> { ids }
  func remove(ids: [String]) { self.ids.subtract(ids) }
  func add(_ reminder: PlannedReminder, timeZoneID: String) throws {
    if fail { throw BirthdayError.invalidResponse }
    ids.insert(reminder.id)
  }
}

final class NotificationTests: XCTestCase {
  func testReplacesStaleBirthdaysWithoutRemovingTestNotification() async throws {
    var preferences = ReminderPreferences()
    preferences.timeZoneID = "UTC"
    let plan = try ReminderPlan.make(
      people: [BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: true)],
      preferences: preferences, now: ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!,
      limit: 1)
    let store = TestStore()
    let count = try await NotificationScheduler().apply(plan, timeZoneID: "UTC", store: store)
    XCTAssertEqual(count, 1)
    let ids = await store.pendingIDs()
    XCTAssertEqual(ids, ["birthday-2027-01-01", "test-notification"])
  }

  func testSchedulingFailureIsNeverReportedAsSuccess() async throws {
    let plan = try ReminderPlan.make(
      people: [BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: true)],
      preferences: ReminderPreferences(), now: Date())
    do {
      _ = try await NotificationScheduler().apply(
        plan, timeZoneID: "UTC", store: TestStore(fail: true))
      XCTFail("Scheduling failure ignored")
    } catch {}
  }
}
