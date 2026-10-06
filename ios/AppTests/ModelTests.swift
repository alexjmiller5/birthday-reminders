import BirthdayCore
import XCTest

@testable import BirthdayReminders

private final class OfflineProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
  }
  override func stopLoading() {}
}

private final class AcceptedProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let body = request.url!.path == "/v1/session"
      ? #"{"name":"synthetic-device","scopes":["tables:read"]}"#
      : #"{"rows":[],"next_cursor":null}"#
    client?.urlProtocol(self, didReceive: HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

final class ModelTests: XCTestCase {
  @MainActor func testFailedCacheSavePreservesAcceptedCredential() async throws {
    let id = UUID().uuidString
    let credentials = ConnectionStore(service: id)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let defaults = UserDefaults(suiteName: id)!
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blocker = directory.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blocker)
    defer {
      try? credentials.clear()
      defaults.removePersistentDomain(forName: id)
      try? FileManager.default.removeItem(at: directory)
    }
    try credentials.save(Connection(
      endpoint: "https://accepted.example", token: "accepted-fixture", source: PeopleSource()))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AcceptedProtocol.self]
    let model = BirthdayModel(
      cache: BirthdayCache(url: blocker.appendingPathComponent("birthdays.json")),
      credentials: credentials, defaults: defaults, session: URLSession(configuration: configuration))
    let connected = await model.installApprovedConnection(
      endpoint: "https://candidate.example", token: "candidate-fixture", source: PeopleSource())
    XCTAssertFalse(connected)
    XCTAssertEqual(model.connection?.token, "accepted-fixture")
    XCTAssertEqual(try credentials.load()?.token, "accepted-fixture")
  }

  @MainActor func testReplacedApprovalCannotReplaceAcceptedConnection() async throws {
    let id = UUID().uuidString
    let credentials = ConnectionStore(service: id)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let defaults = UserDefaults(suiteName: id)!
    defer {
      try? credentials.clear()
      defaults.removePersistentDomain(forName: id)
      try? FileManager.default.removeItem(at: directory)
    }
    try credentials.save(Connection(
      endpoint: "https://accepted.example", token: "accepted-fixture", source: PeopleSource()))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AcceptedProtocol.self]
    let model = BirthdayModel(cache: BirthdayCache(url: directory.appendingPathComponent("cache.json")),
      credentials: credentials, defaults: defaults, session: URLSession(configuration: config))
    var checks = 0
    let connected = await model.installApprovedConnection(endpoint: "https://candidate.example",
      token: "candidate-fixture", source: PeopleSource(), isCurrent: {
        checks += 1
        return checks == 1
      })
    XCTAssertFalse(connected)
    XCTAssertGreaterThan(checks, 1)
    XCTAssertEqual(try credentials.load()?.token, "accepted-fixture")
    XCTAssertEqual(model.connection?.token, "accepted-fixture")
  }

  @MainActor func testDisconnectCannotRaceNotificationAuthorization() async throws {
    try await checkDisconnectDuringAuthorization(sendTest: false)
  }

  @MainActor func testDisconnectCannotRaceTestNotificationScheduling() async throws {
    try await checkDisconnectDuringAuthorization(sendTest: true)
  }

  @MainActor private func checkDisconnectDuringAuthorization(sendTest: Bool) async throws {
    let id = UUID().uuidString
    let credentials = ConnectionStore(service: id)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let cache = BirthdayCache(url: directory.appendingPathComponent("birthdays.json"))
    let defaults = UserDefaults(suiteName: id)!
    defer {
      try? credentials.clear()
      try? cache.clear()
      defaults.removePersistentDomain(forName: id)
    }
    try credentials.save(
      Connection(endpoint: "https://example.invalid", token: "test-value", source: PeopleSource()))
    let started = expectation(description: "OS authorization requested")
    var continuation: CheckedContinuation<Bool, Never>?
    let model = BirthdayModel(
      cache: cache, credentials: credentials, defaults: defaults,
      authorize: {
        await withCheckedContinuation {
          continuation = $0
          started.fulfill()
        }
      })
    let task = Task {
      if sendTest { await model.sendTest() } else { await model.enableNotifications() }
    }
    await fulfillment(of: [started], timeout: 3)
    XCTAssertTrue(model.busy)
    model.disconnect()
    XCTAssertNotNil(model.connection)
    continuation?.resume(returning: true)
    await task.value
    XCTAssertFalse(model.busy)
    model.disconnect()
    XCTAssertNil(model.connection)
  }

  @MainActor func testFailedSyncPreservesSnapshotAndLocalMuteSurvivesRelaunch() async throws {
    let id = UUID().uuidString
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id)
    let cache = BirthdayCache(url: directory.appendingPathComponent("birthdays.json"))
    let credentials = ConnectionStore(service: id)
    let defaults = UserDefaults(suiteName: id)!
    defer {
      try? cache.clear()
      try? credentials.clear()
      defaults.removePersistentDomain(forName: id)
      try? FileManager.default.removeItem(at: directory)
    }
    let person = BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: true)
    let snapshot = BirthdaySnapshot(
      endpoint: "https://example.invalid", source: PeopleSource(), people: [person],
      fetchedAt: Date(timeIntervalSince1970: 1))
    try cache.save(snapshot)
    try credentials.save(
      Connection(endpoint: snapshot.endpoint, token: "test-value", source: PeopleSource()))
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [OfflineProtocol.self]
    let model = BirthdayModel(
      cache: cache, credentials: credentials, defaults: defaults,
      session: URLSession(configuration: config))
    await model.refresh()
    XCTAssertEqual(model.snapshot, snapshot)
    XCTAssertEqual(try cache.load(), snapshot)
    XCTAssertNotNil(model.error)
    await model.mute(person, muted: true)
    let reopened = BirthdayModel(cache: cache, credentials: credentials, defaults: defaults)
    XCTAssertTrue(reopened.preferences.mutedIDs.contains("p1"))
    XCTAssertEqual(reopened.upcoming.map(\.id), ["p1"])
  }
}
