import SwiftUI

/// Welcome screen plus sign-in / create-account form.
struct AuthScreen: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var started = false
    @State private var mode: Mode = .signUp
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @FocusState private var focus: Field?

    enum Mode {
        case signIn, signUp

        var title: String { self == .signIn ? "Welcome back" : "Create your account" }
        var action: String { self == .signIn ? "Sign In" : "Create Account" }
    }

    enum Field: Hashable {
        case firstName, lastName, email, password
    }

    var body: some View {
        ZStack {
            Color.sonderBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if started {
                        formContent
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        landingContent
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Landing

    private var landingContent: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text("Sonder")
                    .font(.georgiaBold(50))
                    .foregroundStyle(Color.sonderAccent)
                Text("Travel that fits you.")
                    .font(.georgiaItalic(18))
                    .foregroundStyle(Color.sonderTextSecond)
            }
            .padding(.top, 28)
            .accessibilityElement(children: .combine)

            Text("Rate the places you actually went — not the whole city. Sonder turns them into a score, a travel personality and where to go next.")
                .font(.georgia(16))
                .foregroundStyle(Color.sonderTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                stepRow(icon: "list.number", title: "Rank what you visited",
                        detail: "Loved it, fine or not for you — then quick head-to-heads.")
                Divider().overlay(Color.sonderDivider)
                stepRow(icon: "sparkles", title: "Get your city score",
                        detail: "Weighted by what matters: neighbourhoods, food, culture.")
                Divider().overlay(Color.sonderDivider)
                stepRow(icon: "airplane.departure", title: "Discover your matches",
                        detail: "A taste profile and destinations picked for you.")
            }
            .sonderCard(padding: 4)

            VStack(spacing: 12) {
                Button("Get Started") { begin(.signUp) }
                    .buttonStyle(.sonderPrimary)

                Button {
                    begin(.signIn)
                } label: {
                    Text("I already have an account")
                        .font(.georgiaBold(15))
                        .foregroundStyle(Color.sonderAccent)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
            }

            if let message = auth.errorMessage, !message.isEmpty {
                messageBanner(message, isError: true)
            }
        }
    }

    private func stepRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.sonderAccent)
                .frame(width: 38, height: 38)
                .background(Color.sonderAccent.opacity(0.12))
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.georgiaBold(15))
                    .foregroundStyle(Color.sonderTextPrimary)
                Text(detail)
                    .font(.georgia(13))
                    .foregroundStyle(Color.sonderTextSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func begin(_ newMode: Mode) {
        auth.clearMessages()
        withAnimation(.easeInOut(duration: 0.25)) {
            mode = newMode
            started = true
        }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    focus = nil
                    auth.clearMessages()
                    withAnimation(.easeInOut(duration: 0.25)) { started = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.sonderAccent)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .accessibilityLabel("Back")
                Spacer()
            }

            VStack(spacing: 6) {
                Text(mode.title)
                    .font(.georgiaBold(28))
                    .foregroundStyle(Color.sonderTextPrimary)
                Text(mode == .signIn ? "Sign in to pick up where you left off." : "It takes less than a minute.")
                    .font(.georgia(15))
                    .foregroundStyle(Color.sonderTextSecond)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 12) {
                if mode == .signUp {
                    HStack(spacing: 12) {
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .firstName)
                            .onSubmit { focus = .lastName }
                            .sonderField()
                        TextField("Last name", text: $lastName)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .lastName)
                            .onSubmit { focus = .email }
                            .sonderField()
                    }
                }

                TextField("Email", text: $email)
                    .textContentType(mode == .signIn ? .username : .emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                    .sonderField()

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(mode == .signIn ? .password : .newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { submit() }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Color.sonderTextSecond)
                            .frame(width: 32, height: 24)
                    }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
                .sonderField()

                if mode == .signUp {
                    Text("Use at least \(AuthStore.minimumPasswordLength) characters.")
                        .font(.georgia(12))
                        .foregroundStyle(Color.sonderTextSecond)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let message = auth.errorMessage, !message.isEmpty {
                messageBanner(message, isError: true)
            }
            if let message = auth.noticeMessage, !message.isEmpty {
                messageBanner(message, isError: false)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if auth.isWorking {
                        ProgressView().tint(Color.sonderOnAccent)
                    }
                    Text(mode.action)
                }
            }
            .buttonStyle(.sonderPrimary)
            .disabled(!canSubmit)

            VStack(spacing: 4) {
                if mode == .signIn {
                    Button("Forgot password?") {
                        focus = nil
                        Task { await auth.sendPasswordReset(email: email) }
                    }
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderAccent)
                    .padding(.vertical, 6)
                    .disabled(auth.isWorking)
                }

                Button {
                    auth.clearMessages()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        mode = mode == .signIn ? .signUp : .signIn
                    }
                } label: {
                    Text(mode == .signIn ? "New here? Create an account" : "Already have an account? Sign in")
                        .font(.georgiaBold(14))
                        .foregroundStyle(Color.sonderAccent)
                        .padding(.vertical, 6)
                }
                .disabled(auth.isWorking)
            }

            if mode == .signUp {
                Text("Your ratings and profile are visible to other Sonder travellers.")
                    .font(.georgia(12))
                    .foregroundStyle(Color.sonderTextSecond)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .onAppear {
            focus = mode == .signUp ? .firstName : .email
        }
    }

    private var canSubmit: Bool {
        guard !auth.isWorking else { return false }
        let hasCredentials = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        if mode == .signIn { return hasCredentials }
        return hasCredentials && !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task {
            switch mode {
            case .signIn:
                await auth.signIn(email: email, password: password)
            case .signUp:
                await auth.signUp(firstName: firstName, lastName: lastName, email: email, password: password)
                // When email confirmation is required, move to sign-in ready for after they confirm.
                if auth.noticeMessage != nil, !auth.isSignedIn {
                    password = ""
                    withAnimation { mode = .signIn }
                }
            }
        }
    }

    private func messageBanner(_ message: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "envelope.badge.fill")
                .foregroundStyle(isError ? Color.sonderDanger : Color.sonderSage)
            Text(message)
                .font(.georgia(14))
                .foregroundStyle(Color.sonderTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background((isError ? Color.sonderDanger : Color.sonderSage).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.smallCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
