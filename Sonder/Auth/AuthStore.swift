import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    enum Phase: Equatable {
        /// Restoring a saved session at launch.
        case loading
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var session: SessionUser?
    @Published private(set) var profile: UserSummary?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let backend: Backend
    private var listener: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
    }

    var isSignedIn: Bool { phase == .signedIn }

    /// Name to greet the user with.
    var displayName: String {
        profile?.name ?? "Traveller"
    }

    var email: String? { session?.email }

    // MARK: - Session lifecycle

    /// Restores any saved session and starts following auth changes. Call once at launch.
    func bootstrap() async {
        guard listener == nil else { return }
        guard backend.isConfigured else {
            phase = .signedOut
            errorMessage = BackendError.notConfigured.errorDescription
            return
        }

        apply(await backend.currentUser())

        let stream = backend.authStateStream()
        listener = Task { [weak self] in
            for await user in stream {
                self?.apply(user)
            }
        }
    }

    private func apply(_ user: SessionUser?) {
        let changed = user?.id != session?.id
        session = user
        phase = user == nil ? .signedOut : .signedIn
        if user == nil {
            profile = nil
        } else if changed || profile == nil {
            Task { await loadProfile() }
        }
    }

    func loadProfile() async {
        guard session != nil else { return }
        if let loaded = try? await backend.fetchMyProfile() {
            profile = loaded
        }
    }

    // MARK: - Actions

    func signUp(firstName: String, lastName: String, email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            errorMessage = "That doesn’t look like a valid email address."
            return
        }
        guard password.count >= Self.minimumPasswordLength else {
            errorMessage = "Please choose a password with at least \(Self.minimumPasswordLength) characters."
            return
        }
        await perform {
            let outcome = try await self.backend.signUp(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            )
            switch outcome {
            case .signedIn:
                self.apply(await self.backend.currentUser())
            case .confirmationRequired:
                self.noticeMessage = "Almost there — we’ve sent a confirmation link to \(email). Open it, then sign in."
            }
        }
    }

    func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            errorMessage = "That doesn’t look like a valid email address."
            return
        }
        await perform {
            try await self.backend.signIn(email: email, password: password)
            self.apply(await self.backend.currentUser())
        }
    }

    func sendPasswordReset(email: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidEmail(email) else {
            errorMessage = "Enter your email address above, then tap “Forgot password?” again."
            return
        }
        await perform {
            try await self.backend.sendPasswordReset(email: email)
            self.noticeMessage = "If an account exists for \(email), a password reset link is on its way."
        }
    }

    func signOut() async {
        await perform {
            try await self.backend.signOut()
            self.apply(nil)
        }
    }

    /// Permanently deletes the account. Returns true on success.
    @discardableResult
    func deleteAccount() async -> Bool {
        var succeeded = false
        await perform {
            try await self.backend.deleteAccount()
            self.apply(nil)
            succeeded = true
        }
        return succeeded
    }

    /// Updates the profile name. Returns true on success.
    @discardableResult
    func updateName(firstName: String, lastName: String) async -> Bool {
        var succeeded = false
        await perform {
            self.profile = try await self.backend.updateMyName(firstName: firstName, lastName: lastName)
            succeeded = true
        }
        return succeeded
    }

    func clearMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        noticeMessage = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = ErrorCopy.message(for: error)
        }
    }

    // MARK: - Validation

    static let minimumPasswordLength = 8

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 254, !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return true
    }
}
