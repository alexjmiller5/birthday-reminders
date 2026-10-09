import BirthdaysCore
import SwiftUI
import UserNotifications

struct BirthdayListView: View {
  @Bindable var model: BirthdayModel
  @State private var showConnection = false
  @State private var showSettings = false
  @State private var showSort = false

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
            Text("Connect Soma to see upcoming birthdays and receive reminders on this phone.")
              .foregroundStyle(.secondary)
            Button("Connect Soma") { showConnection = true }
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
          if !model.canEditOptIns {
            Section {
              Text("Your connection can view birthdays. Approve editing to change notification opt-ins here.")
                .font(.subheadline).foregroundStyle(.secondary)
              Button("Enable opt-in editing") { showConnection = true }
            }
          }
          if model.needsOptInRefresh {
            Section { Button("Refresh notification choices") { Task { await model.refresh() } }.disabled(model.busy) }
          }
          Section {
            if model.upcoming.isEmpty {
              Text("No birthdays yet. Add birthdays in Soma, then pull to refresh.")
                .foregroundStyle(.secondary)
            }
            if !model.upcoming.isEmpty && model.visibleBirthdays.isEmpty {
              Text("No matching birthdays.").foregroundStyle(.secondary)
            }
            ForEach(model.visibleBirthdays) { birthday in
              BirthdayRow(birthday: birthday, model: model)
            }
          } header: {
            Text("Birthdays")
          } footer: {
            Text("Notification opt-ins are shared through Soma. Delivery on this phone also requires notification permission.")
          }
        }
      }
      .navigationTitle("Birthdays")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Settings") { showSettings = true } }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BirthdayListControls(search: $model.search) { showSort = true }
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable { await model.refresh() }
      .overlay {
        if model.busy {
          ProgressView().padding().background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
      }
      .sheet(isPresented: $showConnection) { ConnectionView(model: model) }
      .sheet(isPresented: $showSettings) { ReminderSettingsView(model: model) }
      .sheet(isPresented: $showSort) { BirthdaySortView(model: model) }
    }
  }
  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }
}

private struct BirthdayListControls: View {
  @Binding var search: String
  let showSort: () -> Void
  @FocusState private var searching: Bool

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField("Search by name", text: $search)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .focused($searching)
          .onSubmit { searching = false }
          .frame(minHeight: 44)
        if !search.isEmpty {
          Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
      }
      .padding(.leading, 14)
      .padding(.trailing, search.isEmpty ? 14 : 0)
      .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
      Button("Sort", systemImage: "arrow.up.arrow.down") {
        searching = false
        showSort()
      }
      .labelStyle(.iconOnly)
      .frame(width: 44, height: 44)
      .background(.thinMaterial, in: Circle())
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.bar)
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
      Toggle("Birthday notifications", isOn: Binding(
        get: { birthday.person.enabled },
        set: { value in Task { await model.setOptIn(birthday.person, enabled: value) } }
      ))
      .font(.subheadline)
      .accessibilityLabel("Birthday notifications for \(birthday.person.name)")
      .accessibilityIdentifier("opt-in-\(birthday.id)")
      .disabled(model.busy || !model.canEditOptIns || model.needsOptInRefresh)
      if model.savingPersonID == birthday.id {
        ProgressView("Saving to Soma...").font(.footnote)
      } else if model.isOptInPending(birthday.id) {
        Text("Refresh to confirm this choice. Reminders for this person are paused on this phone.")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if birthday.person.enabled && model.preferences.mutedIDs.contains(birthday.id) {
        Text("Muted on this phone.").font(.footnote).foregroundStyle(.secondary)
        Button("Enable on this phone") { Task { await model.mute(birthday.person, muted: false) } }
          .disabled(model.busy)
      }
    }.padding(.vertical, 5)
  }
}

private struct BirthdaySortView: View {
  @Bindable var model: BirthdayModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.sortRules) { rule in
            VStack(alignment: .leading, spacing: 6) {
              Text(rule.field.title).font(.headline)
              Button(rule.direction, systemImage: "arrow.up.arrow.down") {
                var rules = model.sortRules
                if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                  rules[index].reversed.toggle()
                  model.saveSortRules(rules)
                }
              }
              .accessibilityLabel("\(rule.field.title): \(rule.direction). Reverse order")
              .accessibilityIdentifier("sort-direction-\(rule.field.rawValue)")
            }
            .deleteDisabled(model.sortRules.count == 1)
          }
          .onMove { indices, destination in
            var rules = model.sortRules
            rules.move(fromOffsets: indices, toOffset: destination)
            model.saveSortRules(rules)
          }
          .onDelete { indices in
            var rules = model.sortRules
            rules.remove(atOffsets: indices)
            model.saveSortRules(rules)
          }
        } header: { Text("Sort in this order") }
        footer: { Text("Drag to set priority. Tap a direction to reverse it. Notifications sorts the shared Soma opt-in.") }
        if model.sortRules.count < BirthdaySortRule.Field.allCases.count {
          Section {
            Menu {
              ForEach(BirthdaySortRule.Field.allCases.filter { field in !model.sortRules.contains { $0.field == field } }, id: \.self) { field in
                Button(field.title) { model.saveSortRules(model.sortRules + [BirthdaySortRule(field)]) }
              }
            } label: {
              Text("Add sort rule").frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
          }
        }
        Section { Button("Reset to upcoming first") { model.saveSortRules(BirthdaySortRule.defaults) } }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Sort birthdays")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }
}
