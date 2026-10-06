import BirthdayCore
import SwiftUI

struct ConnectionView: View {
  @Bindable var model: BirthdayModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var endpoint = ""
  @State private var enrollment: EnrollmentSession?

  private var waiting: Bool {
    enrollment?.phase == .waiting || enrollment?.phase == .installing
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Connect your birthdays").font(.title2.bold())
          Text("Enter your Life Data address, then approve Birthday Reminders in your browser. This phone keeps its connection securely in Keychain.")
            .foregroundStyle(.secondary)
        }
        Section("Connection") {
          TextField("Life Data URL", text: $endpoint).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .disabled(waiting)
        } footer: {
          Text("This app requests birthday-only read access. Your opt-in choices stay in Life Data.")
        }
        Section {
          if waiting {
            if let code = enrollment?.approvalCode {
              LabeledContent("Approval code", value: code)
            }
            if let url = enrollment?.approvalURL {
              Button("Open approval link") { openURL(url) }
            }
            Text(enrollment?.phase == .installing ? "Saving connection..." : "Waiting for your approval...")
            Button("Cancel approval") { Task { await enrollment?.cancel() } }
          } else {
            Button("Continue in browser") {
              Task {
                await enrollment?.start(endpoint: endpoint)
                if enrollment?.phase == .connected { dismiss() }
              }
            }.disabled(endpoint.isEmpty || enrollment?.available != true || model.busy)
            if enrollment?.available != true {
              Text("Birthday-only approval is not available yet. You can still test notifications in Settings.")
                .foregroundStyle(.secondary)
            }
          }
          if let failure = enrollment?.failure { Text(failure).foregroundStyle(.red) }
          if let cleanup = enrollment?.cleanupMessage { Text(cleanup).foregroundStyle(.secondary) }
          if let error = model.error { Text(error).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Life Data")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            Task { await enrollment?.cancel(); dismiss() }
          }.disabled(enrollment?.phase == .installing)
        }
      }
      .interactiveDismissDisabled(waiting)
      .task {
        guard enrollment == nil else { return }
        // Fail closed until Life Core publishes the canonical narrow profile.
        // Never substitute the existing full-scope /login binding here.
        enrollment = EnrollmentSession(contract: nil) { endpoint, token, current in
          await model.installApprovedConnection(
            endpoint: endpoint, token: token, source: PeopleSource(), isCurrent: current)
        }
      }
      .onDisappear { Task { await enrollment?.cancel() } }
    }
  }
}
