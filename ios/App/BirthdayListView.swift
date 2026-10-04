import BirthdayCore
import SwiftUI
import UserNotifications

struct BirthdayListView: View {
  @Bindable var model: BirthdayModel
  @State private var showConnection = false
  @State private var showSettings = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 10) {
            Text("Make their day.").font(.largeTitle.bold())
            Text("A little reminder for the people who matter.")
              .font(.body).foregroundStyle(.secondary)
          }
          .padding(.vertical, 12)
          .listRowBackground(Color.clear)
        }
        if let error = model.error {
          Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connection-error") }
        }
        if model.connection == nil {
          Section {
            Text("Your birthdays, together.").font(.title2.bold())
            Text("Connect Life Data to see upcoming birthdays and receive reminders on this phone.")
              .foregroundStyle(.secondary)
            Button("Connect Life Data") { showConnection = true }
              .buttonStyle(.borderedProminent).padding(.vertical, 6)
          }
        } else {
          Section("Reminders") {
            if model.authorization == .denied {
              Text("Notifications are turned off.").foregroundStyle(.secondary)
              Button("Open notification settings") { openSettings() }
            } else if model.authorization == .notDetermined {
              Button("Enable notifications") { Task { await model.enableNotifications() } }
            } else {
              LabeledContent("Scheduled days", value: "\(model.scheduledCount)")
            }
            if let deadline = model.renewBefore {
              Text(
                "Open the app before \(deadline.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: model.preferences.timeZoneID) ?? .current))) to renew your reminders."
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
            if let date = model.snapshot?.fetchedAt {
              Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)
            }
          }
          Section("Upcoming") {
            if model.upcoming.isEmpty {
              Text("No birthdays yet. Add birthdays in Life Data, then pull to refresh.")
                .foregroundStyle(.secondary)
            }
            ForEach(model.upcoming) { birthday in
              BirthdayRow(birthday: birthday, model: model)
            }
          }
        }
      }
      .navigationTitle("Birthdays")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Settings") { showSettings = true } }
      }
      .refreshable { await model.refresh() }
      .overlay {
        if model.busy {
          ProgressView().padding().background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
      }
      .sheet(isPresented: $showConnection) { ConnectionView(model: model) }
      .sheet(isPresented: $showSettings) { ReminderSettingsView(model: model) }
    }
  }
  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }
}

private struct BirthdayRow: View {
  let birthday: UpcomingBirthday
  @Bindable var model: BirthdayModel
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(birthday.person.name).font(.headline)
        Spacer()
        Text(
          birthday.date.formatted(
            Date.FormatStyle(
              date: .abbreviated, time: .omitted,
              timeZone: TimeZone(identifier: model.preferences.timeZoneID) ?? .current))
        )
        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
      }
      if birthday.person.enabled {
        Toggle(
          "Remind on this phone",
          isOn: Binding(
            get: { !model.preferences.mutedIDs.contains(birthday.id) },
            set: { value in Task { await model.mute(birthday.person, muted: !value) } }
          )
        ).font(.subheadline).disabled(model.busy)
      } else {
        Text("Not opted in. Enable birthday reminders in Life Data.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 5)
  }
}
