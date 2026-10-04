import BirthdayCore
import SwiftUI

struct ConnectionView: View {
  @Bindable var model: BirthdayModel
  @Environment(\.dismiss) private var dismiss
  @State private var endpoint = ""
  @State private var credential = ""
  @State private var source = PeopleSource()
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Connect your birthdays").font(.title2.bold())
          Text(
            "Use your Life Data address and a dedicated app credential. Your credential stays in this phone’s Keychain."
          )
          .foregroundStyle(.secondary)
        }
        Section("Connection") {
          TextField("Life Data URL", text: $endpoint).keyboardType(.URL)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          SecureField("App credential", text: $credential)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        Section {
          DisclosureGroup("Birthday source") {
            TextField("Table", text: $source.table)
            TextField("Name column", text: $source.nameColumn)
            TextField("Birthday column", text: $source.birthdayColumn)
            TextField("Opt-in column", text: $source.enabledColumn)
          }.textInputAutocapitalization(.never).autocorrectionDisabled()
        } footer: {
          Text("Birthdays stay in Life Data. This app reads them and honors their opt-in setting.")
        }
        if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
        Section {
          Button("Connect") {
            Task {
              if await model.connect(endpoint: endpoint, token: credential, source: source) {
                credential = ""
                dismiss()
              }
            }
          }
          .disabled(
            model.busy || endpoint.isEmpty || credential.isEmpty
              || [source.table, source.nameColumn, source.birthdayColumn, source.enabledColumn]
                .contains(where: \.isEmpty)
          )
        }
      }
      .navigationTitle("Life Data")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            credential = ""
            dismiss()
          }.disabled(model.busy)
        }
      }
      .interactiveDismissDisabled(model.busy)
    }
  }
}
