import Foundation

public protocol NotificationStore {
  func pendingIDs() async -> Set<String>
  func remove(ids: [String]) async
  func add(_ reminder: PlannedReminder, timeZoneID: String) async throws
}

public struct NotificationScheduler {
  public init() {}
  public func apply(_ plan: ReminderPlan, timeZoneID: String, store: any NotificationStore)
    async throws -> Int
  {
    let desired = Set(plan.reminders.map(\.id))
    let pending = await store.pendingIDs()
    await store.remove(
      ids: Array(pending.filter { $0.hasPrefix("birthday-") }.subtracting(desired)))
    for reminder in plan.reminders { try await store.add(reminder, timeZoneID: timeZoneID) }
    let actual = await store.pendingIDs().filter { $0.hasPrefix("birthday-") }
    guard actual == desired else { throw BirthdayError.invalidResponse }
    return actual.count
  }
}
