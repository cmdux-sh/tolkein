import SwiftUI

struct SettingsView: View {
    @Bindable var model: UsageModel
    @Environment(\.dismiss) private var dismiss
    @State private var workerURL = ""
    @State private var token = ""
    @State private var message: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Worker URL")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("https://tolkeins.example.workers.dev", text: $workerURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Worker URL")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.hasToken ? "Replace read token" : "Read token")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SecureField(model.hasToken ? "Leave blank to keep the saved token" : "Phone read token", text: $token)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Read token")
                    }
                } footer: {
                    Text("Use the phone read token from wrangler secret put READ_TOKEN_PHONE. The write token stays on the Mac. The token is stored in the Keychain and shared with the widget.")
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(message)
                    }
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        Text(isTesting ? "Testing…" : "Test connection")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(isTesting || workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Save") { save() }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .disabled(!canSave)

                    if model.hasToken {
                        Button("Remove token", role: .destructive) {
                            removeToken()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
            .onAppear {
                workerURL = model.workerURL
            }
        }
    }

    private var canSave: Bool {
        !workerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!token.isEmpty || model.hasToken)
    }

    private func save() {
        do {
            try model.save(url: workerURL, token: token)
            token = ""
            message = "Saved."
            Task { await model.refresh() }
        } catch let error as LocalizedError {
            message = error.errorDescription
        } catch {
            message = error.localizedDescription
        }
    }

    private func removeToken() {
        do {
            try model.clearToken()
            token = ""
            message = "Removed the read token from this phone."
        } catch let error as LocalizedError {
            message = error.errorDescription
        } catch {
            message = error.localizedDescription
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        message = await model.testConnection(url: workerURL, token: token)
    }
}
