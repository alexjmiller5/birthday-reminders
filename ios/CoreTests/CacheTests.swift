import XCTest

@testable import BirthdaysCore

final class CacheTests: XCTestCase {
  func testRenamedCacheMigratesSnapshotWithoutLosingOfflineData() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("previous/cache.json")
    let new = root.appendingPathComponent("birthdays/cache.json")
    let snapshot = BirthdaySnapshot(endpoint: "https://hub.example", source: PeopleSource(),
      people: [BirthdayPerson(id: "fixture-id", name: "<person-1>", birthday: "--01-01", enabled: true)],
      fetchedAt: Date(timeIntervalSince1970: 1))
    try BirthdayCache(url: old).save(snapshot)
    let cache = BirthdayCache(url: new, legacyURL: old)
    XCTAssertEqual(try cache.load(), snapshot)
    XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    // A surviving old copy must neither replace new data nor resurrect on disconnect.
    var newer = snapshot.people
    newer.append(BirthdayPerson(id: "fixture-2", name: "<person-2>", birthday: "--02-02", enabled: true))
    let updated = BirthdaySnapshot(endpoint: snapshot.endpoint, source: snapshot.source,
      people: newer, fetchedAt: Date(timeIntervalSince1970: 2))
    try BirthdayCache(url: old).save(snapshot)
    try cache.save(updated)
    XCTAssertEqual(try cache.load(), updated)
    try cache.clear()
    XCTAssertNil(try cache.load())
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
  }

  func testFailedCacheMigrationKeepsReadableOriginal() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let old = root.appendingPathComponent("previous/cache.json")
    let blocker = root.appendingPathComponent("blocked")
    let snapshot = BirthdaySnapshot(endpoint: "https://hub.example", source: PeopleSource(), people: [], fetchedAt: Date())
    try BirthdayCache(url: old).save(snapshot)
    try Data("not a directory".utf8).write(to: blocker)
    let cache = BirthdayCache(url: blocker.appendingPathComponent("cache.json"), legacyURL: old)
    XCTAssertEqual(try cache.load(), snapshot)
    XCTAssertEqual(try BirthdayCache(url: old).load(), snapshot)
  }

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
