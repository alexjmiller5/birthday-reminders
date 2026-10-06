import BirthdaysCore
import Foundation
import UserNotifications

struct LocalNotifications: NotificationStore {
  let center = UNUserNotificationCenter.current()
  func pendingIDs() async -> Set<String> {
    Set(await center.pendingNotificationRequests().map(\.identifier))
  }
  func remove(ids: [String]) async {
    center.removePendingNotificationRequests(withIdentifiers: ids)
  }
  func add(_ reminder: PlannedReminder, timeZoneID: String) async throws {
    let content = UNMutableNotificationContent()
    content.title = reminder.names.count == 1 ? "A birthday to remember" : "Birthdays today"
    content.body =
      reminder.names.joined(separator: ", ")
      + (reminder.names.count == 1 ? " has a birthday today." : " have birthdays today.")
    content.sound = .default
    content.threadIdentifier = "birthdays"
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID)!
    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute], from: reminder.date)
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    try await center.add(
      UNNotificationRequest(
        identifier: reminder.id, content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
  }
  func sendTest() async throws {
    let content = UNMutableNotificationContent()
    content.title = "Birthdays"
    content.body = "Your phone is ready for birthday reminders."
    content.sound = .default
    try await center.add(
      UNNotificationRequest(
        identifier: "test-notification", content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)))
  }
}
