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
  private func checkSave(_ response: Int) async throws {
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
    await model.setOptIn(person, enabled: true)
    XCTAssertEqual(writes, 1)
    XCTAssertEqual(model.snapshot?.people.first?.enabled, response == 200)
    XCTAssertEqual(model.needsOptInRefresh, response != 200)
    XCTAssertFalse(model.busy); XCTAssertNil(model.savingPersonID)
    XCTAssertEqual(model.error == nil, response == 200)
    let reopened = BirthdayModel(cache: cache, credentials: store, defaults: defaults, session: session)
    XCTAssertEqual(reopened.needsOptInRefresh, response != 200)
    XCTAssertEqual(reopened.snapshot?.people.first?.enabled, response == 200)
    if response != 200 {
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
}
