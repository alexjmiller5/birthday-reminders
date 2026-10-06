import Foundation

public struct BirthdaySnapshot: Codable, Equatable, Sendable {
  public let endpoint: String
  public let source: PeopleSource
  public let people: [BirthdayPerson]
  public let fetchedAt: Date
  public init(endpoint: String, source: PeopleSource, people: [BirthdayPerson], fetchedAt: Date) {
    self.endpoint = endpoint
    self.source = source
    self.people = people
    self.fetchedAt = fetchedAt
  }
}

public struct BirthdayCache {
  public let url: URL
  private let legacyURL: URL?
  public init(url: URL, legacyURL: URL? = nil) { self.url = url; self.legacyURL = legacyURL }
  public func load() throws -> BirthdaySnapshot? {
    if FileManager.default.fileExists(atPath: url.path) {
      return try JSONDecoder().decode(BirthdaySnapshot.self, from: Data(contentsOf: url))
    }
    guard let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
    let snapshot = try JSONDecoder().decode(BirthdaySnapshot.self, from: Data(contentsOf: legacyURL))
    // Preserve offline use if a full disk temporarily prevents migration.
    if (try? save(snapshot)) != nil {
      try? FileManager.default.removeItem(at: legacyURL)
      let directory = legacyURL.deletingLastPathComponent()
      if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
        try? FileManager.default.removeItem(at: directory)
      }
    }
    return snapshot
  }
  public func save(_ snapshot: BirthdaySnapshot) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: url.path)
    #endif
  }
  public func clear() throws {
    for location in [url, legacyURL].compactMap({ $0 }) {
      if FileManager.default.fileExists(atPath: location.path) {
        try FileManager.default.removeItem(at: location)
      }
    }
  }
}
