import BirthdaysCore
import XCTest

@testable import Birthdays

final class ConnectionTests: XCTestCase {
  func testCredentialsSurviveRelaunchAndDisconnectRemovesThem() throws {
    let service = "birthdays-test-" + UUID().uuidString
    let store = ConnectionStore(service: service)
    defer { try? store.clear() }
    XCTAssertNil(try store.load())
    try store.save(
      Connection(endpoint: "https://example.invalid", token: "test-value", source: PeopleSource()))
    XCTAssertEqual(try ConnectionStore(service: service).load()?.token, "test-value")
    try store.clear()
    XCTAssertNil(try store.load())
  }
}
