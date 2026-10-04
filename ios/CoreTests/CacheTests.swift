import XCTest

@testable import BirthdayCore

final class CacheTests: XCTestCase {
  func testRelaunchLoadsLastSnapshotAndDisconnectRemovesIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("cache.json")
    let cache = BirthdayCache(url: url)
    XCTAssertNil(try cache.load())
    let snapshot = BirthdaySnapshot(
      endpoint: "https://example.invalid", source: PeopleSource(),
      people: [BirthdayPerson(id: "p1", name: "<person-1>", birthday: "--01-01", enabled: true)],
      fetchedAt: Date())
    try cache.save(snapshot)
    XCTAssertEqual(try BirthdayCache(url: url).load(), snapshot)
    try cache.clear()
    XCTAssertNil(try BirthdayCache(url: url).load())
  }
}
