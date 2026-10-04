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
  public init(id: String, name: String, birthday: String, enabled: Bool) {
    self.id = id
    self.name = name
    self.birthday = birthday
    self.enabled = enabled
  }
}
