import SwiftUI

/// Social feed: what other travellers have been rating.
struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    scopePicker

                    if store.isLoadingFeed && store.feedItems.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 210) }
                    } else if store.feedItems.isEmpty {
                        emptyState
                    } else if store.feedScope == .trending {
                        trendingList
                    } else {
                        ForEach(store.feedItems) { item in
                            FeedCardView(item: item)
                        }
                    }
                }
                .padding(.horizontal, SonderMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sonderScreenBackground()
            .refreshable { await store.refreshFeed() }
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.findPeople) {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Find people")
                }
            }
            .sonderDestinations()
        }
    }

    private var scopePicker: some View {
        Picker("Feed", selection: Binding(
            get: { store.feedScope },
            set: { scope in Task { await store.setFeedScope(scope) } }
        )) {
            ForEach(FeedScope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var emptyState: some View {
        switch store.feedScope {
        case .everyone:
            EmptyStateView(
                icon: "globe.europe.africa",
                title: "Nothing here yet",
                message: "Be the first: rate a city and it will show up here for other travellers.",
                actionTitle: "Rate a city"
            ) {
                store.isAddingCity = true
            }
        case .following:
            if social.followingIds.isEmpty {
                VStack(spacing: 4) {
                    EmptyStateView(
                        icon: "person.2",
                        title: "Follow some travellers",
                        message: "See where the people you follow have been and how they rated it."
                    )
                    NavigationLink(value: Route.findPeople) {
                        Text("Find people")
                    }
                    .buttonStyle(.sonderSecondary)
                    .padding(.bottom, 32)
                }
            } else {
                EmptyStateView(
                    icon: "tray",
                    title: "All quiet",
                    message: "The people you follow haven’t rated anything yet."
                )
            }
        case .trending:
            EmptyStateView(
                icon: "chart.line.uptrend.xyaxis",
                title: "No trends this week",
                message: "Cities rated in the last seven days will appear here."
            )
        }
    }

    private var trendingList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Most rated in the last 7 days")
                .font(.georgia(13))
                .foregroundStyle(Color.sonderTextSecond)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Array(store.trendingCities.enumerated()), id: \.element.id) { index, city in
                TrendingCityRow(city: city, position: index + 1)
            }
        }
    }
}

// MARK: - Feed card

struct FeedCardView: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.user(item.author)) {
                HStack(spacing: 10) {
                    AvatarView(initials: item.author.initials, size: 36, filled: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.userName)
                            .font(.georgiaBold(15))
                            .foregroundStyle(Color.sonderTextPrimary)
                            .lineLimit(1)
                        Text("\(item.action.displayText) · \(item.relativeTime)")
                            .font(.georgia(12))
                            .foregroundStyle(Color.sonderTextSecond)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.userName) \(item.action.displayText), \(item.relativeTime)")
            .accessibilityHint("Opens their profile")

            ZStack(alignment: .bottomLeading) {
                RemoteImage(item.cityPhotoURL, placeholderIcon: "building.2")
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.city)
                            .font(.georgiaBold(22))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !item.country.isEmpty {
                            Text(item.country)
                                .font(.georgia(13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    Spacer(minLength: 8)
                    if let score = item.score {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(ScoreFormat.string(score))
                                .font(.georgiaBold(30))
                                .foregroundStyle(Color.sonderScoreOnPhoto)
                                .monospacedDigit()
                            Text("/ 10")
                                .font(.georgia(13))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .padding(14)
            }
            .frame(height: 190)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                item.score.map { "\(item.placeName), \(ScoreFormat.string($0)) out of 10" } ?? item.placeName
            )

            if let review = item.review, !review.isEmpty {
                Text(review)
                    .font(.georgiaItalic(14))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            }
        }
        .background(Color.sonderSurface)
        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Trending row

struct TrendingCityRow: View {
    let city: TrendingCity
    let position: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.georgiaBold(18))
                .foregroundStyle(position == 1 ? Color.sonderAccent : Color.sonderTextSecond)
                .frame(width: 26)
                .monospacedDigit()

            RemoteImage(city.photoURL, placeholderIcon: "building.2")
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(city.city)
                    .font(.georgiaBold(16))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .lineLimit(1)
                Text(city.ratingCount == 1 ? "1 traveller this week" : "\(city.ratingCount) travellers this week")
                    .font(.georgia(13))
                    .foregroundStyle(Color.sonderTextSecond)
            }
            Spacer(minLength: 8)
            if city.averageScore > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ScoreFormat.string(city.averageScore))
                        .font(.georgiaBold(20))
                        .foregroundStyle(Color.sonderAccent)
                        .monospacedDigit()
                    Text("avg")
                        .font(.georgia(11))
                        .foregroundStyle(Color.sonderTextSecond)
                }
            }
        }
        .padding(10)
        .background(Color.sonderSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Number \(position), \(city.city), rated by \(city.ratingCount) "
            + (city.ratingCount == 1 ? "traveller" : "travellers")
            + (city.averageScore > 0 ? ", average \(ScoreFormat.string(city.averageScore))" : "")
        )
    }
}
