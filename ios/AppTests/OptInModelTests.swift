import BirthdaysCore
import XCTest
@testable import Birthdays

private final class OptInProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, String))!
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@MainActor final class OptInModelTests: XCTestCase {
  func testOptOutCacheFailureCannotRestoreNotificationsAfterOfflineRestart() async throws {
    let id = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let cache = BirthdayCache(url: directory.appendingPathComponent("cache.json"))
    let store = ConnectionStore(service: id), defaults = UserDefaults(suiteName: id)!
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
      try? store.clear(); defaults.removePersistentDomain(forName: id)
    }
    let person = BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: true,
      revision: RowRevision(updatedAt: "2030-01-01T00:00:00.000Z", hubAt: nil))
    let receipt = EnrollmentProfileReceipt(id: BirthdaysAccess.editorProfile, revision: String(repeating: "a", count: 64))
    try store.save(Connection(endpoint: "https://example.invalid", token: "fixture", source: PeopleSource(), enrollmentProfile: receipt))
    try cache.save(BirthdaySnapshot(endpoint: "https://example.invalid", source: PeopleSource(), people: [person], fetchedAt: Date()))
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OptInProtocol.self]
    let session = URLSession(configuration: config)
    let notifications = MemoryNotifications()
    OptInProtocol.handler = { request in
      if request.url!.path == "/v1/session" {
        return (200, String(data: try JSONSerialization.data(withJSONObject: [
          "name": "device:" + String(repeating: "b", count: 64), "scopes": BirthdaysAccess.editorScopes,
          "enrollmentProfile": ["id": receipt.id, "revision": receipt.revision],
          "capabilities": ["row_api": "v1", "schema": "none", "replica_sync": false, "conditional_patch": "revision-v1"],
        ]), encoding: .utf8)!)
      }
      return (200, #"{"id":"p1","revision":{"updated_at":"2030-01-02T00:00:00.000Z","hub_at":"2030-01-02T00:00:00.000Z"}}"#)
    }
    let model = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session,
      notificationStore: notifications, authorizationStatus: { .authorized })
    await model.savePreferences(model.preferences)
    XCTAssertFalse(notifications.reminders.isEmpty)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    await model.setOptIn(person, enabled: false)
    XCTAssertEqual(model.snapshot?.people.first?.enabled, false)
    XCTAssertEqual(try cache.load()?.people.first?.enabled, true, "Old atomic cache must remain intact for this regression")
    XCTAssertTrue(model.needsOptInRefresh)
    XCTAssertTrue(notifications.reminders.isEmpty)
    OptInProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    let reopened = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session,
      notificationStore: notifications, authorizationStatus: { .authorized })
    await reopened.refresh()
    XCTAssertEqual(reopened.snapshot?.people.first?.enabled, true)
    XCTAssertTrue(reopened.needsOptInRefresh)
    XCTAssertTrue(notifications.reminders.isEmpty, "Stale cache must not reschedule the opted-out person")
  }

  private func checkSave(_ response: Int, cacheFailure: Bool = false) async throws {
    let id = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let cache = BirthdayCache(url: directory.appendingPathComponent("cache.json"))
    let store = ConnectionStore(service: id), defaults = UserDefaults(suiteName: id)!
    defer {
      try? store.clear(); defaults.removePersistentDomain(forName: id)
      try? FileManager.default.removeItem(at: directory)
    }
    let person = BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: false,
      revision: RowRevision(updatedAt: "2030-01-01T00:00:00.000Z", hubAt: nil))
    let receipt = EnrollmentProfileReceipt(id: BirthdaysAccess.editorProfile, revision: String(repeating: "a", count: 64))
    try store.save(Connection(endpoint: "https://example.invalid", token: "fixture", source: PeopleSource(), enrollmentProfile: receipt))
    try cache.save(BirthdaySnapshot(endpoint: "https://example.invalid", source: PeopleSource(), people: [person], fetchedAt: Date()))
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OptInProtocol.self]
    let session = URLSession(configuration: config)
    var writes = 0
    OptInProtocol.handler = { request in
      if request.url!.path == "/v1/session" {
        return (200, String(data: try JSONSerialization.data(withJSONObject: [
          "name": "device:" + String(repeating: "b", count: 64), "scopes": BirthdaysAccess.editorScopes,
          "enrollmentProfile": ["id": receipt.id, "revision": receipt.revision],
          "capabilities": ["row_api": "v1", "schema": "none", "replica_sync": false, "conditional_patch": "revision-v1"],
        ]), encoding: .utf8)!)
      }
      if request.url!.path == "/v1/rows/patch" {
        writes += 1
        if response == 0 { throw URLError(.networkConnectionLost) }
        return (response, #"{"id":"p1","revision":{"updated_at":"2030-01-02T00:00:00.000Z","hub_at":"2030-01-02T00:00:00.000Z"}}"#)
      }
      return (200, #"{"rows":[{"id":"p1","name":"<person-1>","birthday":"--01-01","notify_birthday":1,"deleted_at":null,"updated_at":"2030-01-02T00:00:00.000Z","hub_at":"2030-01-02T00:00:00.000Z"}],"next_cursor":null}"#)
    }
    let model = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session)
    if cacheFailure {
      try FileManager.default.removeItem(at: directory)
      try Data("storage blocked".utf8).write(to: directory)
    }
    await model.setOptIn(person, enabled: true)
    let settled = response == 200 && !cacheFailure
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(model.snapshot?.people.first?.enabled, response == 200)
    XCTAssertEqual(model.needsOptInRefresh, !settled)
    XCTAssertFalse(model.busy); XCTAssertNil(model.savingPersonID)
    XCTAssertEqual(model.error == nil, settled)
    let reopened = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session)
    XCTAssertEqual(reopened.needsOptInRefresh, !settled)
    if cacheFailure {
      XCTAssertNil(reopened.snapshot)
      try FileManager.default.removeItem(at: directory)
    } else { XCTAssertEqual(reopened.snapshot?.people.first?.enabled, response == 200) }
    if !settled {
      await reopened.setOptIn(person, enabled: true)
      XCTAssertEqual(writes, 1)
      await reopened.refresh()
      XCTAssertFalse(reopened.needsOptInRefresh)
      XCTAssertEqual(reopened.snapshot?.people.first?.enabled, true)
      XCTAssertEqual(writes, 1)
    }
    model.saveSortRules([BirthdaySortRule(.name, reversed: true), BirthdaySortRule(.notifications)])
    let restored = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session)
    XCTAssertEqual(restored.sortRules, model.sortRules)
  }
  func testConfirmedSavePersistsSharedFlag() async throws { try await checkSave(200) }
  func testConflictPreservesChoiceUntilRefresh() async throws { try await checkSave(409) }
  func testLostAcknowledgmentPersistsRefreshGateWithoutRetry() async throws { try await checkSave(0) }
  func testConfirmedWriteWithCacheFailureKeepsRefreshGate() async throws { try await checkSave(200, cacheFailure: true) }
}

@MainActor private final class MemoryNotifications: NotificationStore {
  var reminders: [String: PlannedReminder] = [:]
  func pendingIDs() async -> Set<String> { Set(reminders.keys) }
  func remove(ids: [String]) async { for id in ids { reminders.removeValue(forKey: id) } }
  func add(_ reminder: PlannedReminder, timeZoneID: String) async throws { reminders[reminder.id] = reminder }
}
