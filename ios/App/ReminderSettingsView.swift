import BirthdaysCore
import SwiftUI

struct ReminderSettingsView: View {
  @Bindable var model: BirthdayModel
  @Environment(\.dismiss) private var dismiss
  @State private var time = Date()
  @State private var zone = ""
  @State private var confirmDisconnect = false
  var body: some View {
    NavigationStack {
      Form {
        Section("Delivery") {
          DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
          Picker("Timezone", selection: $zone) {
            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
          }
          Button("Save reminder settings") {
            var preferences = model.preferences
            preferences.hour = Calendar.current.component(.hour, from: time)
            preferences.minute = Calendar.current.component(.minute, from: time)
            preferences.timeZoneID = zone
            Task { await model.savePreferences(preferences) }
          }.disabled(model.busy)
        }
        Section {
          Button("Send test notification") { Task { await model.sendTest() } }.disabled(model.busy)
          if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
          if model.authorization == .denied {
            Button("Open notification settings") {
              UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
          }
        } footer: {
          Text(
            "Scheduled reminders work while the app is closed. Open it regularly to sync changes and renew the schedule."
          )
        }
        Section("Tasks") {
          Text("Life Data task reminders are not connected yet.").foregroundStyle(.secondary)
        }
        if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
        if model.connection != nil {
          Section {
            Button("Disconnect Life Data", role: .destructive) { confirmDisconnect = true }
              .disabled(model.busy)
          } footer: {
            Text(
              "Removes this phone’s saved connection, birthdays and notifications. Your Life Data records stay intact."
            )
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .onAppear {
        zone = model.preferences.timeZoneID
        time =
          Calendar.current.date(
            from: DateComponents(hour: model.preferences.hour, minute: model.preferences.minute))
          ?? Date()
      }
      .confirmationDialog(
        "Disconnect Life Data?", isPresented: $confirmDisconnect, titleVisibility: .visible
      ) {
        Button("Disconnect", role: .destructive) {
          model.disconnect()
          dismiss()
        }
      }
    }
  }
}
