import Foundation

public struct ReminderPreferences: Codable, Equatable, Sendable {
  public var hour: Int = 9
  public var minute: Int = 0
  public var timeZoneID: String = TimeZone.current.identifier
  public var mutedIDs: Set<String> = []
  public init() {}
}

public struct PlannedReminder: Equatable, Identifiable, Sendable {
  public let id: String
  public let date: Date
  public let names: [String]
}

public struct ReminderPlan: Sendable {
  public let reminders: [PlannedReminder]
  public let renewBefore: Date?
  public static func make(
    people: [BirthdayPerson], preferences: ReminderPreferences,
    now: Date, limit: Int = 60
  ) throws -> ReminderPlan {
    guard (0...23).contains(preferences.hour), (0...59).contains(preferences.minute),
      (1...60).contains(limit), let zone = TimeZone(identifier: preferences.timeZoneID)
    else {
      throw BirthdayError.invalidPreferences
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let year = calendar.component(.year, from: now)
    var groups: [Date: [(String, String)]] = [:]
    for person in people where person.enabled && !preferences.mutedIDs.contains(person.id) {
      guard let birthday = BirthdayDate(person.birthday) else {
        throw BirthdayError.invalidBirthday
      }
      for y in year...(year + 5) {
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        let day = birthday.month == 2 && birthday.day == 29 && !leap ? 28 : birthday.day
        guard
          let date = calendar.date(
            from: DateComponents(
              timeZone: zone, year: y,
              month: birthday.month, day: day, hour: preferences.hour, minute: preferences.minute)),
          date > now
        else { continue }
        groups[date, default: []].append((person.id, person.name))
      }
    }
    let dates = groups.keys.sorted()
    let reminders = dates.prefix(limit).map { date in
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      let id = String(
        format: "birthday-%04d-%02d-%02d", components.year!, components.month!, components.day!)
      return PlannedReminder(
        id: id, date: date, names: groups[date]!.sorted { $0.0 < $1.0 }.map(\.1))
    }
    let horizon = calendar.date(
      from: DateComponents(timeZone: zone, year: year + 6, month: 1, day: 1))
    return ReminderPlan(
      reminders: reminders,
      renewBefore: dates.count > limit ? dates[limit] : (dates.isEmpty ? nil : horizon))
  }
}

public enum BirthdayError: Error, LocalizedError {
  case invalidPreferences, invalidBirthday, invalidEndpoint, invalidResponse, unauthorized
  case http(Int)
  case adminCredential
  public var errorDescription: String? {
    switch self {
    case .invalidPreferences: return "Choose a valid reminder time and timezone."
    case .invalidBirthday: return "A birthday is invalid. Correct it in Life Data, then sync again."
    case .invalidEndpoint:
      return "Enter an HTTPS endpoint without credentials, a query or a fragment."
    case .invalidResponse:
      return
        "Life Data returned an incomplete or invalid response. Your saved birthdays are unchanged."
    case .unauthorized: return "This connection is no longer authorized. Reconnect to Life Data."
    case .http(let status): return "Life Data request failed (HTTP \(status)). Try again later."
    case .adminCredential: return "Use a dedicated app credential, not an operator credential."
    }
  }
}
