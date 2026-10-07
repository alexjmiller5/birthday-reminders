import Foundation

public struct UpcomingBirthday: Identifiable, Sendable {
  public let person: BirthdayPerson
  public let date: Date
  public var id: String { person.id }
  public init(person: BirthdayPerson, date: Date) { self.person = person; self.date = date }
}

public struct BirthdaySortRule: Codable, Equatable, Identifiable, Sendable {
  public enum Field: String, CaseIterable, Codable, Sendable {
    case name, birthday, notifications
    public var title: String {
      switch self {
      case .name: return "Name"
      case .birthday: return "Upcoming birthday"
      case .notifications: return "Notifications"
      }
    }
  }
  public let field: Field
  public var reversed: Bool
  public var id: Field { field }
  public init(_ field: Field, reversed: Bool = false) { self.field = field; self.reversed = reversed }
  public static let defaults = [Self(.birthday)]
  public var direction: String {
    switch field {
    case .name: return reversed ? "Z to A" : "A to Z"
    case .birthday: return reversed ? "Latest first" : "Next first"
    case .notifications: return reversed ? "Disabled first" : "Enabled first"
    }
  }
}

public enum BirthdayListOrder {
  public static func normalized(_ rules: [BirthdaySortRule]) -> [BirthdaySortRule] {
    var seen: Set<BirthdaySortRule.Field> = []
    let unique = rules.filter { seen.insert($0.field).inserted }
    return unique.isEmpty ? BirthdaySortRule.defaults : unique
  }

  public static func apply(_ rows: [UpcomingBirthday], search: String = "",
                           rules: [BirthdaySortRule], locale: Locale = .current) -> [UpcomingBirthday] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    let rules = normalized(rules)
    return rows.filter {
      query.isEmpty || $0.person.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
    }.sorted { left, right in
      for rule in rules {
        let order: ComparisonResult
        switch rule.field {
        case .name:
          order = left.person.name.compare(right.person.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: locale)
        case .birthday:
          order = left.date.compare(right.date)
        case .notifications:
          order = left.person.enabled == right.person.enabled ? .orderedSame : (left.person.enabled ? .orderedAscending : .orderedDescending)
        }
        if order != .orderedSame { return order == (rule.reversed ? .orderedDescending : .orderedAscending) }
      }
      return left.id < right.id
    }
  }
}
