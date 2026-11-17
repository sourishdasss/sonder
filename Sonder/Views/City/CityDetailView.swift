import SwiftUI

/// Detail for one of the signed-in user's cities. Looks the city up live so edits show
/// immediately, and pops when the city is deleted.
struct MyCityDetailView: View {
    let cityID: UUID
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    /// Presented from here (rather than the app root) so editing also works when this screen is
    /// itself shown inside a sheet, e.g. from the map.
    @State private var editing: RatedCity?

    var body: some View {
        if let city = store.city(id: cityID) {
            CityDetailView(city: city, rank: store.rank(of: city), total: store.ratedCities.count)
                .fullScreenCover(item: $editing) { target in
                    RateCityView(city: target.cityData, existing: target)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                editing = city
                            } label: {
                                Label("Edit ratings", systemImage: "pencil")
                            }
                            ShareLink(item: shareText(for: city)) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete city", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("City options")
                    }
                }
                .confirmationDialog(
                    "Delete \(city.cityData.city)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await store.deleteCity(city)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your ratings for this city will be removed. This can’t be undone.")
                }
        } else {
            // The city was deleted (here or on another device).
            Color.sonderBackground
                .ignoresSafeArea()
                .onAppear { dismiss() }
        }
    }

    private func shareText(for city: RatedCity) -> String {
        var text = "I rated \(city.cityData.displayName) \(ScoreFormat.string(city.cumulativeScore))/10 on Sonder"
        if let top = city.topAttractionName, !top.isEmpty {
            text += " — top pick: \(top)"
        }
        return text + "."
    }
}

/// Read-only presentation of a rated city: score, write-up, category breakdown and ranked places.
struct CityDetailView: View {
    let city: RatedCity
    var ownerName: String?
    var rank: Int?
    var total: Int = 0

    private var placesByCategory: [(category: AttractionCategory, places: [ScoredPlace])] {
        let grouped = Dictionary(grouping: city.scoredPlaces.filter { $0.attraction.category != .general }) {
            $0.attraction.category
        }
        return AttractionCategory.placeCategories.compactMap { category in
            guard let places = grouped[category], !places.isEmpty else { return nil }
            return (category, places.sorted { $0.rank < $1.rank })
        }
    }

    private var vibe: ScoredPlace? {
        city.scoredPlaces.first { $0.attraction.category == .general }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                VStack(alignment: .leading, spacing: 22) {
                    writeUp
                    breakdown
                    places
                    if !city.hasPlaceDetails {
                        Label(
                            ownerName == nil
                                ? "This visit was logged with an earlier version of Sonder, which didn’t save the individual places. Choose Edit ratings to add them."
                                : "This visit was logged with an earlier version of Sonder, which didn’t save the individual places.",
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                        .sonderCard(padding: 14, radius: 16)
                    }
                    if let createdAt = city.createdAt {
                        Text("Logged \(createdAt.formatted(date: .long, time: .omitted))")
                            .font(.georgia(12))
                            .foregroundStyle(Color.sonderTextSecond)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal, SonderMetrics.screenPadding)
                .padding(.bottom, 28)
            }
        }
        // The hero photo runs under a transparent bar, so keep the soft system edge here.
        .sonderScreenBackground(hardTopEdge: false)
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(city.cityData.photoURL, placeholderIcon: "building.2")
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                if let ownerName {
                    Text("\(ownerName)’s visit")
                        .font(.georgia(13))
                        .foregroundStyle(.white.opacity(0.85))
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(city.cityData.city)
                        .font(.georgiaBold(34))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if !city.cityData.flag.isEmpty {
                        Text(city.cityData.flag).font(.system(size: 26))
                    }
                }
                if !city.cityData.country.isEmpty {
                    Text(city.cityData.country)
                        .font(.georgia(16))
                        .foregroundStyle(.white.opacity(0.85))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ScoreFormat.string(city.cumulativeScore))
                        .font(.custom("Georgia-Bold", size: 60, relativeTo: .largeTitle))
                        .foregroundStyle(Color.sonderScoreOnPhoto)
                        .monospacedDigit()
                    Text("/ 10")
                        .font(.georgia(20))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let rank, total > 1 {
                            Text("#\(rank) of \(total)")
                                .font(.georgiaBold(15))
                                .foregroundStyle(.white)
                        }
                        Text(city.placeCount == 1 ? "1 place rated" : "\(city.placeCount) places rated")
                            .font(.georgia(13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.top, 4)
            }
            .padding(SonderMetrics.screenPadding)
        }
        .frame(height: 340)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(city.cityData.displayName), \(ScoreFormat.string(city.cumulativeScore)) out of 10, "
            + (city.placeCount == 1 ? "1 place rated" : "\(city.placeCount) places rated")
        )
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Write-up

    @ViewBuilder
    private var writeUp: some View {
        if !city.highlight.isEmpty || !city.summary.isEmpty || !city.wouldRecommendIf.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if !city.highlight.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Color.sonderAccent)
                        Text(city.highlight)
                            .font(.georgiaBold(16))
                            .foregroundStyle(Color.sonderTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !city.summary.isEmpty {
                    Text(city.summary)
                        .font(.georgia(15))
                        .foregroundStyle(Color.sonderTextPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !city.wouldRecommendIf.isEmpty {
                    Divider().overlay(Color.sonderDivider)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Who it’s for")
                            .font(.georgiaBold(13))
                            .foregroundStyle(Color.sonderSage)
                        Text(city.wouldRecommendIf)
                            .font(.georgiaItalic(15))
                            .foregroundStyle(Color.sonderTextSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .sonderCard()
        }
    }

    // MARK: - Breakdown

    @ViewBuilder
    private var breakdown: some View {
        let items = city.sortedBreakdown
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Score breakdown")
                    .sonderSectionTitle()
                VStack(spacing: 14) {
                    ForEach(items, id: \.category) { item in
                        ScoreBar(category: item.category, score: item.score)
                    }
                }
                .sonderCard()
                Text("Neighbourhoods and the overall vibe count most toward the score; landmarks count least.")
                    .font(.georgia(12))
                    .foregroundStyle(Color.sonderTextSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Places

    @ViewBuilder
    private var places: some View {
        if !placesByCategory.isEmpty || vibe != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Places, ranked")
                    .sonderSectionTitle()

                ForEach(placesByCategory, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(group.category.rawValue, systemImage: group.category.icon)
                            .font(.georgiaBold(15))
                            .foregroundStyle(Color.sonderTextPrimary)
                            .padding(.bottom, 6)

                        ForEach(Array(group.places.enumerated()), id: \.element.id) { index, place in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.georgiaBold(16))
                                    .foregroundStyle(index == 0 ? Color.sonderAccent : Color.sonderTextSecond)
                                    .frame(width: 22, alignment: .trailing)
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.attraction.name)
                                        .font(.georgia(15))
                                        .foregroundStyle(Color.sonderTextPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    SentimentChip(sentiment: place.sentiment)
                                }
                                Spacer(minLength: 8)
                                Text(ScoreFormat.string(place.score))
                                    .font(.georgiaBold(16))
                                    .foregroundStyle(Color.sonderAccent)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "Number \(index + 1), \(place.attraction.name), \(place.sentiment.shortLabel), "
                                + "\(ScoreFormat.string(place.score)) out of 10"
                            )
                            if index < group.places.count - 1 {
                                Divider().overlay(Color.sonderDivider).padding(.leading, 34)
                            }
                        }
                    }
                    .sonderCard(padding: 14, radius: 16)
                }

                if let vibe {
                    HStack(spacing: 12) {
                        Image(systemName: AttractionCategory.general.icon)
                            .foregroundStyle(Color.sonderSage)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overall vibe")
                                .font(.georgiaBold(15))
                                .foregroundStyle(Color.sonderTextPrimary)
                            Text("Walkability, atmosphere, getting around")
                                .font(.georgia(12))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        Spacer(minLength: 8)
                        SentimentChip(sentiment: vibe.sentiment)
                    }
                    .sonderCard(padding: 14, radius: 16)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
