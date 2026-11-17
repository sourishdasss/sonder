import SwiftUI

/// The "rate a city" flow: add the places you visited, say how each felt, rank similar ones
/// head-to-head, rate the city's overall vibe, then save to get the city score.
struct RateCityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    /// Called after the visit is saved and the result screen is dismissed.
    var onFinished: (() -> Void)?

    @State private var city: CityData
    @State private var draft: CityRatingDraft
    @State private var existing: RatedCity?
    @StateObject private var search = AttractionPOISearch()

    @State private var query = ""
    @State private var suggestions: [Attraction] = []
    @State private var customPlaces: [Attraction] = []
    @State private var ratingTarget: Attraction?
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedCity: RatedCity?
    @State private var showDiscardConfirm = false
    @FocusState private var searchFocused: Bool

    init(city: CityData, existing: RatedCity? = nil, onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
        _city = State(initialValue: city)
        _existing = State(initialValue: existing)
        _draft = State(initialValue: existing.map(CityRatingDraft.init(ratedCity:)) ?? CityRatingDraft())
    }

    private var isUpdate: Bool { existing != nil }

    var body: some View {
        NavigationStack {
            Group {
                if let savedCity {
                    ScoreRevealView(city: savedCity, rank: store.rank(of: savedCity), total: store.ratedCities.count, isUpdate: isUpdate) {
                        onFinished?()
                        dismiss()
                    }
                    .transition(.opacity)
                } else {
                    editor
                }
            }
            .sonderScreenBackground()
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .task { await prepare() }
    }

    // MARK: - Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if isUpdate && !hasChanges {
                    Label("You’ve rated \(city.city) before — edit your ranking below.", systemImage: "arrow.triangle.2.circlepath")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderSage)
                }
                searchSection
                suggestionsSection
                rankingsSection
                vibeSection

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderDanger)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sonderDanger.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.smallCornerRadius, style: .continuous))
                }
            }
            .padding(SonderMetrics.screenPadding)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { saveBar }
        .navigationTitle(isUpdate ? "Update visit" : "Rate your visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if hasChanges {
                        showDiscardConfirm = true
                    } else {
                        dismiss()
                    }
                }
                .disabled(isSaving)
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .sheet(item: $ratingTarget) { target in
            PlaceRatingSheet(attraction: target, cityName: city.city, draft: draft) { placed, sentiment, index in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    draft.insert(placed, sentiment: sentiment, at: index)
                }
                if customPlaces.contains(where: { $0.id == placed.id }) {
                    customPlaces.removeAll { $0.id == placed.id }
                    customPlaces.append(placed)
                }
                hasChanges = true
                errorMessage = nil
            }
        }
        .onChange(of: query) { _, text in
            search.updateQuery(text)
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(city.photoURL, placeholderIcon: "building.2")
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                if !city.flag.isEmpty {
                    Text(city.flag).font(.system(size: 28))
                }
                Text(city.city)
                    .font(.georgiaBold(26))
                    .foregroundStyle(.white)
                if !city.country.isEmpty {
                    Text(city.country)
                        .font(.georgia(14))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(16)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(city.displayName)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Search

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where did you go?")
                .sonderSectionTitle()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.sonderTextSecond)
                TextField("Search restaurants, museums, parks…", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                        search.reset()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.sonderTextSecond)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .sonderField()

            if !trimmedQuery.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if search.isLoading && search.results.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching \(city.city)…")
                                .font(.georgia(14))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        .padding(.vertical, 12)
                    }

                    ForEach(search.results) { result in
                        let added = draft.contains(name: result.title)
                        Button {
                            add(Attraction(name: result.title, category: result.category))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: result.category.icon)
                                    .foregroundStyle(Color.sonderSage)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .font(.georgiaBold(15))
                                        .foregroundStyle(Color.sonderTextPrimary)
                                        .multilineTextAlignment(.leading)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.georgia(12))
                                            .foregroundStyle(Color.sonderTextSecond)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(added ? Color.sonderSage : Color.sonderAccent)
                            }
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(added)
                        Divider().overlay(Color.sonderDivider)
                    }

                    if !draft.contains(name: trimmedQuery),
                       !search.results.contains(where: { $0.title.lowercased() == trimmedQuery.lowercased() }) {
                        Button {
                            addCustomPlace(named: trimmedQuery)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.square.dashed")
                                    .foregroundStyle(Color.sonderAccent)
                                    .frame(width: 24)
                                Text("Add “\(trimmedQuery)” as a new place")
                                    .font(.georgia(15))
                                    .foregroundStyle(Color.sonderAccent)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.sonderSurface)
                .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.smallCornerRadius, style: .continuous))
            }
        }
    }

    // MARK: - Suggestions

    private var openSuggestions: [Attraction] {
        suggestions.filter { !draft.contains(name: $0.name) }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if trimmedQuery.isEmpty, !openSuggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Popular in \(city.city)")
                    .font(.georgiaBold(15))
                    .foregroundStyle(Color.sonderTextSecond)
                FlowLayout(spacing: 8) {
                    ForEach(openSuggestions.prefix(12)) { attraction in
                        Button {
                            add(attraction)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: attraction.category.icon)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color.sonderSage)
                                Text(attraction.name)
                                    .font(.georgia(13))
                                    .foregroundStyle(Color.sonderTextPrimary)
                                    .lineLimit(1)
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.sonderAccent)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.sonderSurface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.sonderDivider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add \(attraction.name)")
                    }
                }
            }
        }
    }

    // MARK: - Rankings

    private var liveScore: ScoringEngine.CityScore {
        ScoringEngine.cityScore(for: draft.entries)
    }

    @ViewBuilder
    private var rankingsSection: some View {
        if draft.hasPlaces {
            let scores = Dictionary(liveScore.places.map { ($0.id, $0.score) }, uniquingKeysWith: { a, _ in a })
            VStack(alignment: .leading, spacing: 14) {
                Text("Your ranking")
                    .sonderSectionTitle()
                ForEach(draft.activeCategories) { category in
                    categoryCard(category, scores: scores)
                }
            }
        } else {
            EmptyStateView(
                icon: "list.number",
                title: "Your ranking starts here",
                message: "Add the places you visited. For each one you’ll say how it felt, then compare it with similar spots."
            )
            .sonderCard(padding: 0)
        }
    }

    private func categoryCard(_ category: AttractionCategory, scores: [UUID: Double]) -> some View {
        let places = draft.places(in: category)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sonderSage)
                Text(category.rawValue)
                    .font(.georgiaBold(15))
                    .foregroundStyle(Color.sonderTextPrimary)
                Spacer()
            }
            .padding(.bottom, 6)

            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
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

                    if let score = scores[place.id] {
                        Text(ScoreFormat.string(score))
                            .font(.georgiaBold(15))
                            .foregroundStyle(Color.sonderAccent)
                            .monospacedDigit()
                    }

                    Menu {
                        Button {
                            rerank(place)
                        } label: {
                            Label("Change rating", systemImage: "arrow.up.arrow.down")
                        }
                        Button(role: .destructive) {
                            remove(place)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.sonderTextSecond)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Options for \(place.attraction.name)")
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                if index < places.count - 1 {
                    Divider().overlay(Color.sonderDivider).padding(.leading, 34)
                }
            }
        }
        .sonderCard(padding: 14, radius: 16)
    }

    // MARK: - Overall vibe

    private var vibeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overall vibe")
                    .sonderSectionTitle()
                Text("Walkability, atmosphere and how easy \(city.city) was to get around. Optional.")
                    .font(.georgia(13))
                    .foregroundStyle(Color.sonderTextSecond)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(VisitSentiment.allCases) { option in
                    let selected = draft.generalAppeal == option
                    Button {
                        draft.generalAppeal = selected ? nil : option
                        hasChanges = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(.system(size: 16, weight: .semibold))
                            Text(option.shortLabel)
                                .font(.georgia(12))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .foregroundStyle(selected ? Color.sonderOnAccent : SentimentChip.color(for: option))
                        .background(selected ? Color.sonderAccent : Color.sonderSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.sonderDivider, lineWidth: selected ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Overall vibe: \(option.shortLabel)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: draft.generalAppeal)
        }
    }

    // MARK: - Save bar

    private var saveBar: some View {
        VStack(spacing: 8) {
            if draft.hasPlaces {
                HStack(alignment: .firstTextBaseline) {
                    Text(draft.placeCount == 1 ? "1 place ranked" : "\(draft.placeCount) places ranked")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                    Spacer()
                    Text("Score so far")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                    Text(ScoreFormat.string(liveScore.cumulativeScore))
                        .font(.georgiaBold(18))
                        .foregroundStyle(Color.sonderAccent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: liveScore.cumulativeScore)
                }
            }
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView().tint(Color.sonderOnAccent)
                    }
                    Text(isSaving ? "Scoring your visit…" : (isUpdate ? "Update visit" : "Save visit"))
                }
            }
            .buttonStyle(.sonderPrimary)
            .disabled(!draft.hasPlaces || isSaving || (isUpdate && !hasChanges))
        }
        .padding(.horizontal, SonderMetrics.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.bar)
    }

    // MARK: - Actions

    private func prepare() async {
        // Opened from search for a city that's already rated: continue from the saved ranking.
        if existing == nil, let match = store.existingCity(matching: city) {
            existing = match
            draft = CityRatingDraft(ratedCity: match)
            if city.photoURL.isEmpty { city.photoURL = match.cityData.photoURL }
            if city.flag.isEmpty { city.flag = match.cityData.flag }
            if city.coordinate == nil {
                city.latitude = match.cityData.latitude
                city.longitude = match.cityData.longitude
            }
        }

        // Curated suggestions first, then places other travellers have added.
        var pool = (Attractions.seed(city: city.city, flag: city.flag)?.attractions ?? city.attractions)
            .filter { $0.category != .general }
        suggestions = pool

        let snapshot = city
        async let photo = Self.resolvePhoto(for: snapshot)
        async let community = store.communityPlaces(for: snapshot)
        async let center = search.configure(for: snapshot)

        let (url, communityPlaces, coordinate) = await (photo, community, center)
        if let url, city.photoURL.isEmpty {
            city.photoURL = url
        }
        if city.coordinate == nil, let coordinate {
            city.latitude = coordinate.latitude
            city.longitude = coordinate.longitude
        }
        let known = Set(pool.map(\.dedupeKey))
        pool.append(contentsOf: communityPlaces.filter { !known.contains($0.dedupeKey) && $0.category != .general })
        suggestions = pool
    }

    private static func resolvePhoto(for city: CityData) async -> String? {
        guard city.photoURL.isEmpty else { return nil }
        return await CityPhotoService.shared.photoURL(city: city.city, country: city.country)
    }

    private func add(_ attraction: Attraction) {
        guard !draft.contains(name: attraction.name) else { return }
        searchFocused = false
        query = ""
        search.reset()
        ratingTarget = attraction
    }

    private func addCustomPlace(named name: String) {
        let attraction = Attraction(name: name, category: .experience)
        customPlaces.append(attraction)
        add(attraction)
    }

    private func rerank(_ place: RankedPlace) {
        withAnimation { draft.remove(id: place.id) }
        hasChanges = true
        ratingTarget = place.attraction
    }

    private func remove(_ place: RankedPlace) {
        withAnimation { draft.remove(id: place.id) }
        hasChanges = true
    }

    private func save() async {
        guard !isSaving else { return }
        searchFocused = false
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved = try await store.saveCity(city: city, draft: draft, existing: existing)
            // Share brand-new places so other travellers get them as suggestions.
            let shared = customPlaces.filter { draft.contains(name: $0.name) }
            let cityData = city
            Task {
                for place in shared {
                    await store.shareCustomPlace(place, in: cityData)
                }
            }
            hasChanges = false
            withAnimation(.easeInOut(duration: 0.3)) { savedCity = saved }
        } catch {
            errorMessage = ErrorCopy.message(for: error)
        }
    }
}

// MARK: - Score reveal

/// The payoff screen after saving a visit.
struct ScoreRevealView: View {
    let city: RatedCity
    let rank: Int?
    let total: Int
    let isUpdate: Bool
    var onDone: () -> Void

    @State private var shownScore = 0.0
    @State private var revealed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack(alignment: .bottom) {
                    RemoteImage(city.cityData.photoURL, placeholderIcon: "building.2")
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    VStack(spacing: 2) {
                        Text("\(city.cityData.city) \(city.cityData.flag)")
                            .font(.georgiaBold(26))
                            .foregroundStyle(.white)
                        if !city.cityData.country.isEmpty {
                            Text(city.cityData.country)
                                .font(.georgia(14))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))

                VStack(spacing: 4) {
                    Text(isUpdate ? "Updated score" : "Your score")
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderTextSecond)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ScoreFormat.string(shownScore))
                            .font(.custom("Georgia-Bold", size: 76, relativeTo: .largeTitle))
                            .foregroundStyle(Color.sonderAccent)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: shownScore))
                        Text("/ 10")
                            .font(.georgia(20))
                            .foregroundStyle(Color.sonderTextSecond)
                    }
                    if let rank, total > 1 {
                        Text("#\(rank) of \(total) in your rankings")
                            .font(.georgiaBold(14))
                            .foregroundStyle(Color.sonderSage)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(city.cityData.city) scored \(ScoreFormat.string(city.cumulativeScore)) out of 10")

                VStack(alignment: .leading, spacing: 14) {
                    if !city.highlight.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Color.sonderAccent)
                            Text(city.highlight)
                                .font(.georgiaBold(15))
                                .foregroundStyle(Color.sonderTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !city.summary.isEmpty {
                        Text(city.summary)
                            .font(.georgia(15))
                            .foregroundStyle(Color.sonderTextSecond)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .sonderCard()
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 12)

                if !city.sortedBreakdown.isEmpty {
                    VStack(spacing: 14) {
                        ForEach(city.sortedBreakdown, id: \.category) { item in
                            ScoreBar(category: item.category, score: item.score)
                        }
                    }
                    .sonderCard()
                    .opacity(revealed ? 1 : 0)
                }
            }
            .padding(SonderMetrics.screenPadding)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Done", action: onDone)
                .buttonStyle(.sonderPrimary)
                .padding(.horizontal, SonderMetrics.screenPadding)
                .padding(.vertical, 10)
                .background(.bar)
        }
        .navigationBarBackButtonHidden()
        .navigationTitle(isUpdate ? "Visit updated" : "Visit saved")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: revealed)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shownScore = city.cumulativeScore }
            withAnimation(.easeOut(duration: 0.45).delay(0.5)) { revealed = true }
        }
    }
}
