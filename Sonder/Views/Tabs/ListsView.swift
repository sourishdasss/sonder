import SwiftUI

/// The user's rated places, as city rankings or grouped by category.
struct ListsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: ListMode = .rankings
    @State private var cityToDelete: RatedCity?
    @Namespace private var zoom

    enum ListMode: String, CaseIterable, Identifiable {
        case rankings = "Rankings"
        case categories = "Categories"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("View", selection: $mode) {
                        ForEach(ListMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !store.hasLoaded {
                        loadingContent
                    } else if store.ratedCities.isEmpty {
                        emptyContent
                    } else if mode == .rankings {
                        rankingsContent
                    } else {
                        categoriesContent
                    }
                }
                .padding(SonderMetrics.screenPadding)
            }
            .sonderScreenBackground()
            .refreshable { await store.refreshAll() }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.isAddingCity = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add a city")
                }
            }
            .sonderDestinations(zoomNamespace: zoom)
            .confirmationDialog(
                "Delete \(cityToDelete?.cityData.city ?? "this city")?",
                isPresented: Binding(
                    get: { cityToDelete != nil },
                    set: { if !$0 { cityToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: cityToDelete
            ) { city in
                Button("Delete", role: .destructive) {
                    Task { await store.deleteCity(city) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Your ratings for this city will be removed. This can’t be undone.")
            }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var loadingContent: some View {
        if let error = store.loadError {
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "Couldn’t load your cities",
                message: error,
                actionTitle: "Try again"
            ) {
                Task { await store.refreshAll() }
            }
        } else {
            VStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
            }
        }
    }

    private var emptyContent: some View {
        EmptyStateView(
            icon: "map",
            title: "No cities yet",
            message: "Log your first destination and rank the places you visited to get its score.",
            actionTitle: "Add your first city"
        ) {
            store.isAddingCity = true
        }
        .sonderCard(padding: 0)
    }

    // MARK: - Rankings

    private var rankingsContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if let average = store.averageCityScore, store.ratedCities.count > 1 {
                Text("\(store.ratedCities.count) cities · average \(ScoreFormat.string(average))")
                    .font(.georgia(13))
                    .foregroundStyle(Color.sonderTextSecond)
            }
            ForEach(Array(store.ratedCities.enumerated()), id: \.element.id) { index, city in
                NavigationLink(value: Route.myCity(city.id)) {
                    CityCardView(city: city, rank: index + 1)
                }
                .buttonStyle(.plain)
                .cityZoomSource(id: city.id, in: zoom)
                .contextMenu {
                    Button {
                        store.editingCity = city
                    } label: {
                        Label("Edit ratings", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        cityToDelete = city
                    } label: {
                        Label("Delete city", systemImage: "trash")
                    }
                }
                .accessibilityHint("Shows the full breakdown")
            }
        }
    }

    // MARK: - Categories

    private struct CategoryEntry: Identifiable {
        let place: ScoredPlace
        let city: RatedCity
        var id: String { "\(city.id.uuidString)-\(place.id.uuidString)" }
    }

    private func entries(for category: AttractionCategory) -> [CategoryEntry] {
        store.ratedCities
            .flatMap { city in
                city.scoredPlaces
                    .filter { $0.attraction.category == category }
                    .map { CategoryEntry(place: $0, city: city) }
            }
            .sorted { lhs, rhs in
                if lhs.place.score != rhs.place.score { return lhs.place.score > rhs.place.score }
                return lhs.place.attraction.name < rhs.place.attraction.name
            }
    }

    private var categoriesContent: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(AttractionCategory.placeCategories) { category in
                CategorySection(category: category, entries: entries(for: category))
            }
        }
    }

    private struct CategorySection: View {
        let category: AttractionCategory
        let entries: [CategoryEntry]
        @State private var expanded = false

        private var visible: [CategoryEntry] {
            expanded ? entries : Array(entries.prefix(5))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sonderSage)
                    Text(category.rawValue)
                        .font(.georgiaBold(16))
                        .foregroundStyle(Color.sonderTextPrimary)
                    Spacer()
                    Text("\(entries.count)")
                        .font(.georgiaBold(14))
                        .foregroundStyle(Color.sonderTextSecond)
                        .accessibilityLabel(entries.count == 1 ? "1 place" : "\(entries.count) places")
                }
                .padding(.bottom, 4)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if entries.isEmpty {
                    Text("Nothing logged in this category yet.")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(value: Route.myCity(entry.city.id)) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.georgiaBold(15))
                                    .foregroundStyle(index == 0 ? Color.sonderAccent : Color.sonderTextSecond)
                                    .frame(width: 22, alignment: .trailing)
                                    .monospacedDigit()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.place.attraction.name)
                                        .font(.georgia(15))
                                        .foregroundStyle(Color.sonderTextPrimary)
                                        .multilineTextAlignment(.leading)
                                    Text("\(entry.city.cityData.city) \(entry.city.cityData.flag)")
                                        .font(.georgia(12))
                                        .foregroundStyle(Color.sonderTextSecond)
                                }
                                Spacer(minLength: 8)
                                SentimentChip(sentiment: entry.place.sentiment, compact: true)
                                Text(ScoreFormat.string(entry.place.score))
                                    .font(.georgiaBold(15))
                                    .foregroundStyle(Color.sonderAccent)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "Number \(index + 1), \(entry.place.attraction.name) in \(entry.city.cityData.city), "
                            + "\(ScoreFormat.string(entry.place.score)) out of 10"
                        )
                    }
                    if entries.count > 5 {
                        Button(expanded ? "Show less" : "Show all \(entries.count)") {
                            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                        }
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderAccent)
                        .padding(.top, 4)
                    }
                }
            }
            .sonderCard(padding: 14, radius: 16)
        }
    }
}
