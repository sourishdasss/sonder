import SwiftUI

/// The signed-in user's travel identity: personality, taste, stats, top cities, recommendations.
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var social: SocialStore
    @Namespace private var zoom

    private var me: UserSummary? {
        guard let session = auth.session else { return nil }
        return auth.profile ?? UserSummary(id: session.id, displayName: auth.displayName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 24) {
                        header
                        PersonalityCard(
                            profile: store.travelProfile,
                            isRefreshing: store.isRefreshingProfile,
                            citiesNeeded: store.citiesUntilProfile
                        )
                        statsRow
                        tasteSection
                        topCitiesSection
                    }
                    .padding(.horizontal, SonderMetrics.screenPadding)

                    if !store.travelProfile.recommendations.isEmpty {
                        FutureRecommendationsView(recommendations: store.travelProfile.recommendations)
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .sonderScreenBackground()
            .refreshable {
                await store.refreshAll()
                await social.refresh()
                await auth.loadProfile()
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sonderDestinations(zoomNamespace: zoom)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                AvatarView(initials: me?.initials ?? "S", size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.displayName)
                        .font(.georgiaBold(22))
                        .foregroundStyle(Color.sonderTextPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text("Travel that fits you.")
                        .font(.georgiaItalic(14))
                        .foregroundStyle(Color.sonderTextSecond)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            if let me {
                HStack(spacing: 0) {
                    NavigationLink(value: Route.followers(me)) {
                        followStat(count: social.myCounts.followers, label: social.myCounts.followers == 1 ? "Follower" : "Followers")
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color.sonderDivider).frame(width: 1, height: 30)
                    NavigationLink(value: Route.following(me)) {
                        followStat(count: social.myCounts.following, label: "Following")
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Color.sonderDivider).frame(width: 1, height: 30)
                    NavigationLink(value: Route.findPeople) {
                        VStack(spacing: 3) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.sonderAccent)
                                .frame(height: 24)
                            Text("Find people")
                                .font(.georgia(12))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .background(Color.sonderSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func followStat(count: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.georgiaBold(20))
                .foregroundStyle(Color.sonderTextPrimary)
                .monospacedDigit()
                .frame(height: 24)
            Text(label)
                .font(.georgia(12))
                .foregroundStyle(Color.sonderTextSecond)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(label)")
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(store.ratedCities.count)", label: store.ratedCities.count == 1 ? "City" : "Cities")
            divider
            statCell(value: "\(store.totalPlacesRated)", label: "Places rated")
            divider
            statCell(value: "\(store.countriesVisited)", label: store.countriesVisited == 1 ? "Country" : "Countries")
            if let average = store.averageCityScore {
                divider
                statCell(value: ScoreFormat.string(average), label: "Avg score")
            }
        }
        .padding(.vertical, 16)
        .background(Color.sonderSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.georgiaBold(22))
                .foregroundStyle(Color.sonderAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
            Text(label)
                .font(.georgia(11))
                .foregroundStyle(Color.sonderTextSecond)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private var divider: some View {
        Rectangle().fill(Color.sonderDivider).frame(width: 1, height: 36)
    }

    // MARK: - Taste

    @ViewBuilder
    private var tasteSection: some View {
        let breakdown = store.tasteBreakdown
        if !breakdown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your taste")
                        .sonderSectionTitle()
                    if let favourite = store.favouriteCategory {
                        Label(favourite.shortName, systemImage: "heart.fill")
                            .font(.georgia(12))
                            .foregroundStyle(Color.sonderAccent)
                            .fixedSize()
                            .accessibilityLabel("Favourite category: \(favourite.shortName)")
                    }
                }
                VStack(spacing: 14) {
                    ForEach(breakdown, id: \.category) { item in
                        ScoreBar(category: item.category, score: item.score)
                    }
                }
                .sonderCard()
                Text("Average score of the places you’ve rated in each category.")
                    .font(.georgia(12))
                    .foregroundStyle(Color.sonderTextSecond)
            }
        }
    }

    // MARK: - Top cities

    private var topCitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Top Cities")
                    .sonderSectionTitle()
                if store.ratedCities.count > 3 {
                    Button("See all") { store.selectedTab = .lists }
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderAccent)
                        .fixedSize()
                }
            }

            if !store.hasLoaded {
                SkeletonCard()
            } else if store.ratedCities.isEmpty {
                EmptyStateView(
                    icon: "mappin.and.ellipse",
                    title: "Your rankings start here",
                    message: "Rate the places you visited in a city to see it here.",
                    actionTitle: "Add a city"
                ) {
                    store.isAddingCity = true
                }
                .sonderCard(padding: 0)
            } else {
                ForEach(Array(store.ratedCities.prefix(3).enumerated()), id: \.element.id) { index, city in
                    NavigationLink(value: Route.myCity(city.id)) {
                        CityCardView(city: city, rank: index + 1)
                    }
                    .buttonStyle(.plain)
                    .cityZoomSource(id: city.id, in: zoom)
                }
            }
        }
    }
}

// MARK: - Personality card

/// Travel personality, description and taste traits. Shared by own and other people's profiles.
struct PersonalityCard: View {
    let profile: TravelProfile
    var isRefreshing = false
    /// How many more cities are needed to unlock the personality (own profile only).
    var citiesNeeded = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Travel Personality", systemImage: "sparkles")
                    .font(.georgia(12))
                    .foregroundStyle(Color.sonderTextSecond)
                Spacer()
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.sonderAccent)
                        .accessibilityLabel("Updating your profile")
                }
            }

            Text(profile.personalityType)
                .font(.georgiaItalic(26))
                .foregroundStyle(Color.sonderTextPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(profile.personalityDescription)
                .font(.georgia(15))
                .foregroundStyle(Color.sonderTextSecond)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if !profile.tasteTraits.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(profile.tasteTraits.enumerated()), id: \.offset) { _, trait in
                        TagChip(text: trait)
                    }
                }
            } else if citiesNeeded > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(
                        value: Double(AppStore.profileThreshold - citiesNeeded),
                        total: Double(AppStore.profileThreshold)
                    )
                    .tint(Color.sonderAccent)
                    Text(citiesNeeded == 1
                         ? "Rate 1 more city to unlock your personality."
                         : "Rate \(citiesNeeded) more cities to unlock your personality.")
                        .font(.georgiaItalic(13))
                        .foregroundStyle(Color.sonderTextSecond)
                }
            }
        }
        .sonderCard(padding: 18)
        .accessibilityElement(children: .combine)
    }
}
