import XCTest
@testable import BirthdaysCore

@MainActor final class OptInTests: XCTestCase {
  private let revision = RowRevision(updatedAt: "2030-01-01T00:00:00.000Z", hubAt: "2030-01-01T00:00:01.000Z")
  private func client() throws -> LifeDataClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return try LifeDataClient(endpoint: "https://example.invalid", token: "fixture", session: URLSession(configuration: config))
  }
  private func body(_ request: URLRequest) throws -> [String: Any] {
    if let data = request.httpBody { return try JSONSerialization.jsonObject(with: data) as! [String: Any] }
    let stream = request.httpBodyStream!
    stream.open(); defer { stream.close() }
    var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&bytes, maxLength: bytes.count)
      if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
    }
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
  }
  private var person: BirthdayPerson {
    BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--02-29", enabled: false, revision: revision)
  }
  private var contract: EnrollmentContract {
    EnrollmentContract(approvalPath: { _ in "/unused" }, validate: { value in
      guard value["fixture"] as? Bool == true else { throw BirthdayError.unauthorized }
      return EnrollmentProfileReceipt(id: "fixture-editor", revision: String(repeating: "a", count: 64))
    }, revoked: { _ in false })
  }

  func testPatchValidatesSessionAndSendsOnlyFlagWithExactReadRevision() async throws {
    var paths: [String] = []
    StubProtocol.handler = { request in
      paths.append(request.url!.path)
      if paths.count == 1 { return (200, #"{"fixture":true}"#) }
      let body = try self.body(request)
      XCTAssertEqual(Set(body.keys), ["table", "id", "values", "expected_revision"])
      XCTAssertEqual(body["table"] as? String, "people")
      XCTAssertEqual(body["id"] as? String, "p1")
      XCTAssertEqual(body["values"] as? [String: Int], ["notify_birthday": 1])
      XCTAssertEqual(body["expected_revision"] as? [String: String], ["updated_at": self.revision.updatedAt, "hub_at": self.revision.hubAt!])
      return (200, #"{"id":"p1","revision":{"updated_at":"2030-01-02T00:00:00.000Z","hub_at":"2030-01-02T00:00:01.000Z"}}"#)
    }
    let saved = try await client().setOptIn(person, enabled: true, source: PeopleSource(), contract: contract)
    XCTAssertEqual(paths, ["/v1/session", "/v1/rows/patch"])
    XCTAssertTrue(saved.enabled)
    XCTAssertEqual(saved.name, person.name)
    XCTAssertEqual(saved.revision?.updatedAt, "2030-01-02T00:00:00.000Z")
  }

  func testDeniedSessionNeverWritesAndReadOnlySnapshotCannotWrite() async throws {
    var requests = 0
    StubProtocol.handler = { _ in requests += 1; return (200, "{}") }
    do { _ = try await client().setOptIn(person, enabled: true, source: PeopleSource(), contract: contract); XCTFail("Accepted unapproved session") } catch {}
    XCTAssertEqual(requests, 1)
    let readOnly = BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--02-29", enabled: false)
    do { _ = try await client().setOptIn(readOnly, enabled: true, source: PeopleSource(), contract: contract); XCTFail("Wrote without revision") } catch {}
    XCTAssertEqual(requests, 1)
  }

  func testConflictOfflineAndMalformedReceiptsNeverRetryOrClaimSuccess() async throws {
    for response in [(409, "{}"), (200, "{}"), (200, #"{"id":"other","revision":{"updated_at":"x","hub_at":"x"}}"#), (200, #"{"id":"p1","revision":{"updated_at":"x","hub_at":"x"}}"#), (0, "")] {
      var requests = 0
      StubProtocol.handler = { _ in
        requests += 1
        if requests == 1 { return (200, #"{"fixture":true}"#) }
        if response.0 == 0 { throw URLError(.networkConnectionLost) }
        return response
      }
      do { _ = try await client().setOptIn(person, enabled: true, source: PeopleSource(), contract: contract); XCTFail("Unconfirmed save accepted") } catch {}
      XCTAssertEqual(requests, 2)
    }
  }

  func testEditorPullRequiresRevisionsAndOldCacheStillDecodes() async throws {
    let old = #"{"id":"p1","name":"<person-1>","birthday":"--02-29","enabled":false}"#
    XCTAssertNil(try JSONDecoder().decode(BirthdayPerson.self, from: Data(old.utf8)).revision)
    StubProtocol.handler = { request in
      let body = try self.body(request)
      XCTAssertEqual(Set(body["columns"] as! [String]), ["id", "name", "birthday", "notify_birthday", "deleted_at", "updated_at", "hub_at"])
      return (200, #"{"rows":[{"id":"p1","name":"<person-1>","birthday":"--02-29","notify_birthday":0,"deleted_at":null}],"next_cursor":null}"#)
    }
    do { _ = try await client().people(source: PeopleSource(), includeRevisions: true); XCTFail("Accepted missing revision") } catch {}
  }
}
