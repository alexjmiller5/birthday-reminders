import BirthdayCore
import SwiftUI

struct ConnectionView: View {
  @Bindable var model: BirthdayModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var endpoint = ""
  @State private var enrollment: EnrollmentSession?
  @State private var showCleanup = false

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
        Section {
          TextField("Life Data URL", text: $endpoint).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .disabled(waiting)
        } header: {
          Text("Connection")
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
                if enrollment?.phase == .connected, enrollment?.cleanupMessage == nil { dismiss() }
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
            Task {
              await enrollment?.cancel()
              if enrollment?.cleanupMessage != nil { showCleanup = true }
              else { dismiss() }
            }
          }.disabled(enrollment?.phase == .installing || enrollment?.isCleaningUp == true)
        }
      }
      .alert("Approval cleanup", isPresented: $showCleanup) {
        Button("Close", role: .cancel) { dismiss() }
      } message: {
        Text(enrollment?.cleanupMessage ?? "")
      }
      .interactiveDismissDisabled(waiting || enrollment?.cleanupMessage != nil)
      .task {
        guard enrollment == nil else { return }
        do {
          // Public service-owned profile, separate from the server Tasks writer.
          let policy = try CoreEnrollmentPolicy(profileID: "birthday-reminders-reader-v1", scopes: [
            "tables:read:people:birthday", "tables:read:people:deleted_at", "tables:read:people:id",
            "tables:read:people:name", "tables:read:people:notify_birthday",
          ])
          enrollment = EnrollmentSession(contract: policy.contract) { endpoint, token, receipt, current, accepted in
            await model.installApprovedConnection(
              endpoint: endpoint, token: token, source: PeopleSource(), enrollmentProfile: receipt,
              isCurrent: current, accepted: accepted)
          }
        } catch {
          model.error = "The approval policy could not be loaded. Try reopening the app."
        }
      }
      .onDisappear { Task { await enrollment?.cancel() } }
    }
  }
}
