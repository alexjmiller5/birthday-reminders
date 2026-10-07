import Foundation

public struct BirthdayDate: Codable, Equatable, Sendable {
  public let month: Int
  public let day: Int
  public init?(_ value: String) {
    guard value.range(of: #"^([0-9]{4}|-)-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
    else {
      return nil
    }
    let parts = value.suffix(5).split(separator: "-")
    guard let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
    let year = value.hasPrefix("--") ? 2000 : Int(value.prefix(4))!
    guard year > 0 else { return nil }
    let calendar = Calendar(identifier: .gregorian)
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
      calendar.component(.month, from: date) == month,
      calendar.component(.day, from: date) == day
    else { return nil }
    self.month = month
    self.day = day
  }
}

public struct BirthdayPerson: Codable, Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let birthday: String
  public let enabled: Bool
  public let revision: RowRevision?
  public init(id: String, name: String, birthday: String, enabled: Bool, revision: RowRevision? = nil) {
    self.id = id
    self.name = name
    self.birthday = birthday
    self.enabled = enabled
    self.revision = revision
  }
}

public struct RowRevision: Codable, Equatable, Sendable {
  public let updatedAt: String
  public let hubAt: String?
  public init(updatedAt: String, hubAt: String?) { self.updatedAt = updatedAt; self.hubAt = hubAt }

  static func parse(_ row: [String: Any]) throws -> Self {
    func valid(_ value: String) -> Bool {
      let format = ISO8601DateFormatter()
      format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      guard let date = format.date(from: value) else { return false }
      return format.string(from: date) == value
    }
    guard let updated = row["updated_at"] as? String, valid(updated), row.keys.contains("hub_at"),
      row["hub_at"] is NSNull || (row["hub_at"] as? String).map(valid) == true
    else { throw BirthdayError.invalidResponse }
    return Self(updatedAt: updated, hubAt: row["hub_at"] as? String)
  }
}
