import SwiftUI

/// Account and app settings: name, sign out, delete account, about.
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: AppStore

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var didLoadName = false
    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showFinalDeleteConfirm = false

    private var nameChanged: Bool {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !first.isEmpty && (first != (auth.profile?.firstName ?? "") || last != (auth.profile?.lastName ?? ""))
    }

    var body: some View {
        Form {
            Section {
                TextField("First name", text: $firstName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                TextField("Last name", text: $lastName)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                if nameChanged {
                    Button {
                        Task {
                            if await auth.updateName(firstName: firstName, lastName: lastName) {
                                Toaster.shared.show("Name updated", style: .success)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Save name")
                            if auth.isWorking {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(auth.isWorking)
                }
            } header: {
                Text("Name")
            } footer: {
                Text("Shown on your profile and next to your ratings in the feed.")
            }
            .listRowBackground(Color.sonderSurface)

            Section("Account") {
                if let email = auth.email {
                    LabeledContent("Email", value: email)
                }
                Button("Sign Out") { showSignOutConfirm = true }
                    .disabled(auth.isWorking)
            }
            .listRowBackground(Color.sonderSurface)

            Section {
                LabeledContent("Summaries written by", value: store.isAIEnabled ? "Claude" : "On-device")
                LabeledContent("Version", value: Config.appVersion)
            } header: {
                Text("About")
            } footer: {
                Text(store.isAIEnabled
                     ? "City summaries and your travel personality are written by Claude from your ratings. Scores are always calculated on your device."
                     : "Scores, summaries and your travel personality are all calculated on your device.")
            }
            .listRowBackground(Color.sonderSurface)

            Section {
                Button("Delete Account", role: .destructive) { showDeleteConfirm = true }
                    .disabled(auth.isWorking)
            } footer: {
                Text("Permanently deletes your account, ratings, photos and follows.")
            }
            .listRowBackground(Color.sonderSurface)

            if let message = auth.errorMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderDanger)
                }
                .listRowBackground(Color.sonderSurface)
            }
        }
        .scrollContentBackground(.hidden)
        .sonderScreenBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            auth.clearMessages()
            loadName()
        }
        .onChange(of: auth.profile) { _, _ in
            if !didLoadName { loadName() }
        }
        .confirmationDialog("Sign out of Sonder?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Continue", role: .destructive) { showFinalDeleteConfirm = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your ratings, city scores, photos and follows will be removed.")
        }
        .alert("This can’t be undone", isPresented: $showFinalDeleteConfirm) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    let userId = auth.session?.id
                    if await auth.deleteAccount(), let userId {
                        store.clearCache(userId: userId)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Sonder account and all of its data will be permanently deleted.")
        }
    }

    private func loadName() {
        guard let profile = auth.profile else { return }
        firstName = profile.firstName
        lastName = profile.lastName
        if firstName.isEmpty && lastName.isEmpty {
            // Older accounts only have a display name: split it as a starting point.
            let parts = profile.name.split(separator: " ", maxSplits: 1).map(String.init)
            if profile.name != "Traveller" {
                firstName = parts.first ?? ""
                lastName = parts.count > 1 ? parts[1] : ""
            }
        }
        didLoadName = true
    }
}
