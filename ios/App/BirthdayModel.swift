import BirthdayCore
import Foundation
import Observation
import UserNotifications

struct UpcomingBirthday: Identifiable {
  let person: BirthdayPerson
  let date: Date
  var id: String { person.id }
}

@MainActor @Observable
final class BirthdayModel {
  private(set) var connection: Connection?
  private(set) var snapshot: BirthdaySnapshot?
  private(set) var upcoming: [UpcomingBirthday] = []
  private(set) var authorization: UNAuthorizationStatus = .notDetermined
  private(set) var scheduledCount = 0
  private(set) var renewBefore: Date?
  private(set) var busy = false
  var error: String?
  var notice: String?
  var preferences: ReminderPreferences
  private let cache: BirthdayCache
  private let credentials: ConnectionStore
  private let defaults: UserDefaults
  private let session: URLSession
  private let authorize: () async throws -> Bool
  private let notifications = LocalNotifications()

  init(
    cache: BirthdayCache = BirthdayCache(
      url: URL.applicationSupportDirectory.appendingPathComponent(
        "BirthdayReminders/birthdays.json")),
    credentials: ConnectionStore = ConnectionStore(), defaults: UserDefaults = .standard,
    session: URLSession = .shared,
    authorize: @escaping () async throws -> Bool = {
      try await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound, .badge,
      ])
    }
  ) {
    self.cache = cache
    self.credentials = credentials
    self.defaults = defaults
    self.session = session
    self.authorize = authorize
    preferences =
      defaults.data(forKey: "reminder-preferences")
      .flatMap { try? JSONDecoder().decode(ReminderPreferences.self, from: $0) }
      ?? ReminderPreferences()
    do {
      connection = try credentials.load()
      if let saved = try cache.load(), let connection,
        saved.endpoint == connection.endpoint, saved.source == connection.source
      {
        snapshot = saved
      }
      rebuildUpcoming()
    } catch { self.error = "Saved data could not be loaded. Reconnect to Life Data." }
  }

  // Called only after EnrollmentSession validates the candidate identity/profile.
  func installApprovedConnection(
    endpoint: String, token: String, source: PeopleSource,
    isCurrent: @escaping @MainActor () -> Bool = { true }
  ) async -> Bool {
    guard !busy, isCurrent() else { return false }
    busy = true
    defer { busy = false }
    do {
      let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
      let client = try LifeDataClient(endpoint: endpoint, token: token, session: session)
      let people = try await client.people(source: source)
      let value = BirthdaySnapshot(
        endpoint: endpoint, source: source, people: people, fetchedAt: Date())
      let newConnection = Connection(endpoint: endpoint, token: token, source: source)
      try Task.checkCancellation()
      guard isCurrent() else { throw CancellationError() }
      let previousSnapshot = try? cache.load()
      do {
        try cache.save(value)
        // Keychain is the acceptance commit point. A failed cache write must
        // never replace the previously accepted credential.
        try credentials.save(newConnection)
      } catch {
        if let previousSnapshot { try? cache.save(previousSnapshot) }
        else { try? cache.clear() }
        throw error
      }
      connection = newConnection
      snapshot = value
      error = nil
      rebuildUpcoming()
      await reschedule()
      return true
    } catch {
      report(error)
      return false
    }
  }

  func refresh() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    await updateAuthorization()
    guard let connection else { return }
    do {
      let client = try LifeDataClient(
        endpoint: connection.endpoint, token: connection.token, session: session)
      let people = try await client.people(source: connection.source)
      let value = BirthdaySnapshot(
        endpoint: connection.endpoint, source: connection.source, people: people, fetchedAt: Date())
      try cache.save(value)
      snapshot = value
      error = nil
    } catch { report(error) }
    rebuildUpcoming()
    await reschedule()
  }

  func savePreferences(_ value: ReminderPreferences) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try ReminderPlan.make(people: [], preferences: value, now: Date())
      let data = try JSONEncoder().encode(value)
      defaults.set(data, forKey: "reminder-preferences")
      preferences = value
      rebuildUpcoming()
      await reschedule()
    } catch { report(error) }
  }

  func mute(_ person: BirthdayPerson, muted: Bool) async {
    var value = preferences
    if muted { value.mutedIDs.insert(person.id) } else { value.mutedIDs.remove(person.id) }
    await savePreferences(value)
  }

  func enableNotifications() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await authorize()
      await reschedule()
    } catch { report(error) }
  }

  func sendTest() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      _ = try await authorize()
      await reschedule()
      guard authorization == .authorized || authorization == .provisional else { return }
      try await notifications.sendTest()
      notice = "Lock your phone or leave the app. A test notification will arrive in 10 seconds."
    } catch { report(error) }
  }

  func disconnect() {
    guard !busy else {
      error = "Wait for the current operation to finish, then disconnect."
      return
    }
    do {
      try credentials.clear()
      notifications.center.removeAllPendingNotificationRequests()
      notifications.center.removeAllDeliveredNotifications()
      connection = nil
      snapshot = nil
      upcoming = []
      scheduledCount = 0
      renewBefore = nil
      preferences.mutedIDs = []
      defaults.set(try JSONEncoder().encode(preferences), forKey: "reminder-preferences")
      try cache.clear()
      error = nil
    } catch { report(error) }
  }

  private func updateAuthorization() async {
    authorization = await notifications.center.notificationSettings().authorizationStatus
  }

  private func reschedule() async {
    await updateAuthorization()
    scheduledCount = 0
    renewBefore = nil
    guard authorization == .authorized || authorization == .provisional else { return }
    do {
      let plan = try ReminderPlan.make(
        people: snapshot?.people ?? [], preferences: preferences, now: Date())
      scheduledCount = try await NotificationScheduler().apply(
        plan, timeZoneID: preferences.timeZoneID, store: notifications)
      renewBefore = plan.renewBefore
    } catch { report(error) }
  }

  private func rebuildUpcoming() {
    var displayPreferences = preferences
    displayPreferences.mutedIDs = []
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: preferences.timeZoneID) ?? .current
    let today = calendar.startOfDay(for: Date()).addingTimeInterval(-1)
    upcoming = (snapshot?.people ?? []).compactMap { person in
      let visible = BirthdayPerson(
        id: person.id, name: person.name, birthday: person.birthday, enabled: true)
      guard
        let date = try? ReminderPlan.make(
          people: [visible], preferences: displayPreferences, now: today, limit: 1
        ).reminders.first?.date
      else { return nil }
      return UpcomingBirthday(person: person, date: date)
    }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
  }

  private func report(_ error: Error) {
    if let error = error as? BirthdayError {
      self.error = error.localizedDescription
    } else if let error = error as? KeychainError {
      self.error = error.localizedDescription
    } else {
      self.error = "The operation could not finish. Check your connection and try again."
    }
  }
}
