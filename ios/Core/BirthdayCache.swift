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
  public init(url: URL) { self.url = url }
  public func load() throws -> BirthdaySnapshot? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try JSONDecoder().decode(BirthdaySnapshot.self, from: Data(contentsOf: url))
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
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
  }
}
