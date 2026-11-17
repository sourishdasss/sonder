import SwiftUI

// MARK: - Another traveller's profile

struct UserProfileView: View {
    let user: UserSummary
    @EnvironmentObject private var social: SocialStore

    @State private var cities: [RatedCity] = []
    @State private var travelProfile: TravelProfile?
    @State private var counts: FollowCounts = .zero
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if let travelProfile, !travelProfile.isPlaceholder {
                    PersonalityCard(profile: travelProfile)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(cities.isEmpty ? "Cities" : "Cities · \(cities.count)")
                        .sonderSectionTitle()

                    if isLoading {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 78) }
                    } else if let loadError {
                        EmptyStateView(
                            icon: "wifi.exclamationmark",
                            title: "Couldn’t load this profile",
                            message: loadError,
                            actionTitle: "Try again"
                        ) {
                            Task { await load() }
                        }
                    } else if cities.isEmpty {
                        EmptyStateView(
                            icon: "map",
                            title: "No cities yet",
                            message: "\(user.name) hasn’t rated any cities so far."
                        )
                        .sonderCard(padding: 0)
                    } else {
                        ForEach(cities) { city in
                            NavigationLink(value: Route.city(CitySnapshot(city: city, ownerName: user.name))) {
                                CityRowView(city: city)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(SonderMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .sonderScreenBackground()
        .navigationTitle(user.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                AvatarView(initials: user.initials, size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.georgiaBold(22))
                        .foregroundStyle(Color.sonderTextPrimary)
                        .lineLimit(2)
                    if social.isMe(user.id) {
                        Text("This is you")
                            .font(.georgiaItalic(14))
                            .foregroundStyle(Color.sonderTextSecond)
                    }
                }
                Spacer(minLength: 8)
                FollowButton(user: user)
            }

            HStack(spacing: 0) {
                NavigationLink(value: Route.followers(user)) {
                    countCell(counts.followers, counts.followers == 1 ? "Follower" : "Followers")
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.sonderDivider).frame(width: 1, height: 30)
                NavigationLink(value: Route.following(user)) {
                    countCell(counts.following, "Following")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .background(Color.sonderSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        // Keep the follower count in step with the follow button.
        .onChange(of: social.isFollowing(user.id)) { _, following in
            counts.followers = max(0, counts.followers + (following ? 1 : -1))
        }
    }

    private func countCell(_ count: Int, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.georgiaBold(20))
                .foregroundStyle(Color.sonderTextPrimary)
                .monospacedDigit()
            Text(label)
                .font(.georgia(12))
                .foregroundStyle(Color.sonderTextSecond)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(label)")
    }

    private func load() async {
        loadError = nil
        async let loadedCounts = try? social.counts(for: user.id)
        async let loadedProfile = try? social.travelProfile(of: user.id)
        do {
            cities = try await social.cities(of: user.id)
        } catch {
            if cities.isEmpty { loadError = ErrorCopy.message(for: error) }
        }
        if let value = await loadedCounts { counts = value }
        travelProfile = await loadedProfile
        isLoading = false
    }
}

// MARK: - Find people

struct FindPeopleView: View {
    @EnvironmentObject private var social: SocialStore

    @State private var query = ""
    @State private var results: [UserSummary] = []
    @State private var suggestions: [UserSummary] = []
    @State private var isSearching = false
    @State private var hasLoadedSuggestions = false
    @State private var errorMessage: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderDanger)
                    .listRowBackground(Color.sonderSurface)
            }

            if trimmedQuery.count >= 2 {
                Section {
                    if isSearching && results.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching…")
                                .font(.georgia(14))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        .listRowBackground(Color.sonderSurface)
                    } else if results.isEmpty {
                        Text("No travellers found for “\(trimmedQuery)”.")
                            .font(.georgia(14))
                            .foregroundStyle(Color.sonderTextSecond)
                            .listRowBackground(Color.sonderSurface)
                    } else {
                        ForEach(results) { user in
                            personRow(user)
                        }
                    }
                }
            } else {
                Section {
                    if !hasLoadedSuggestions {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading travellers…")
                                .font(.georgia(14))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        .listRowBackground(Color.sonderSurface)
                    } else if suggestions.isEmpty {
                        Text("No one else is here yet. Invite a friend to compare travel taste.")
                            .font(.georgia(14))
                            .foregroundStyle(Color.sonderTextSecond)
                            .listRowBackground(Color.sonderSurface)
                    } else {
                        ForEach(suggestions) { user in
                            personRow(user)
                        }
                    }
                } header: {
                    Text("Travellers on Sonder")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sonderScreenBackground()
        .navigationTitle("Find People")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .task(id: trimmedQuery) {
            await runSearch()
        }
        .task {
            await loadSuggestions()
        }
    }

    private func personRow(_ user: UserSummary) -> some View {
        // A plain row with a trailing follow button; tapping the row opens the profile.
        ZStack {
            NavigationLink(value: Route.user(user)) { EmptyView() }
                .opacity(0)
            UserRow(user: user)
        }
        .listRowBackground(Color.sonderSurface)
    }

    private func loadSuggestions() async {
        guard !hasLoadedSuggestions else { return }
        do {
            suggestions = try await social.suggestedUsers()
        } catch {
            errorMessage = ErrorCopy.message(for: error)
        }
        hasLoadedSuggestions = true
    }

    private func runSearch() async {
        let text = trimmedQuery
        guard text.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        // Debounce: `.task(id:)` cancels this when the query changes again.
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        do {
            results = try await social.search(text)
            errorMessage = nil
        } catch {
            if !Task.isCancelled { errorMessage = ErrorCopy.message(for: error) }
        }
        isSearching = false
    }
}

// MARK: - Followers / following

struct FollowListView: View {
    enum Mode {
        case followers, following

        var title: String { self == .followers ? "Followers" : "Following" }
    }

    let user: UserSummary
    let mode: Mode
    @EnvironmentObject private var social: SocialStore

    @State private var people: [UserSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading…")
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderTextSecond)
                }
                .listRowBackground(Color.sonderSurface)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderDanger)
                    .listRowBackground(Color.sonderSurface)
            } else if people.isEmpty {
                Text(emptyText)
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderTextSecond)
                    .listRowBackground(Color.sonderSurface)
            } else {
                ForEach(people) { person in
                    ZStack {
                        NavigationLink(value: Route.user(person)) { EmptyView() }
                            .opacity(0)
                        UserRow(user: person)
                    }
                    .listRowBackground(Color.sonderSurface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .sonderScreenBackground()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private var emptyText: String {
        let isMe = social.isMe(user.id)
        switch mode {
        case .followers:
            return isMe ? "No followers yet." : "\(user.name) has no followers yet."
        case .following:
            return isMe ? "You’re not following anyone yet." : "\(user.name) isn’t following anyone yet."
        }
    }

    private func load() async {
        do {
            switch mode {
            case .followers: people = try await social.followers(of: user.id)
            case .following: people = try await social.following(of: user.id)
            }
            errorMessage = nil
        } catch {
            errorMessage = ErrorCopy.message(for: error)
        }
        isLoading = false
    }
}
