import MapKit
import SwiftUI

/// City search: type any city or town in the world, or pick a popular destination.
struct AddCityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @StateObject private var citySearch = CitySearchCompleterService()

    @State private var query = ""
    @State private var selectedCity: CityData?
    @State private var isResolving = false
    @State private var isSearchingFullQuery = false
    @State private var fullSearchResults: [ResolvedCityPlace] = []
    @State private var searchMessage: String?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsTypedFallback: Bool {
        !trimmedQuery.isEmpty
            && !citySearch.isLoading
            && !isSearchingFullQuery
            && citySearch.suggestions.isEmpty
            && fullSearchResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    popularSection
                } else {
                    resultsSections
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .sonderScreenBackground()
            .overlay {
                if isResolving {
                    ZStack {
                        Color.black.opacity(0.15).ignoresSafeArea()
                        ProgressView()
                            .controlSize(.large)
                            .padding(22)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .navigationTitle("Add a City")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search any city or town"
            )
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .onChange(of: query) { _, text in
                searchMessage = nil
                fullSearchResults = []
                citySearch.updateQueryFragment(text)
            }
            .onSubmit(of: .search) {
                Task { await runFullSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(item: $selectedCity) { city in
                RateCityView(city: city) {
                    // Saved: close the whole add-city flow.
                    store.isAddingCity = false
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Popular destinations

    private var popularSection: some View {
        Section {
            ForEach(Attractions.allCities) { seed in
                let rated = store.existingCity(matching: seed)
                Button {
                    selectedCity = Attractions.makeCity(city: seed.city, country: seed.country)
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(seed.photoURL, placeholderIcon: "building.2")
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(seed.city) \(seed.flag)")
                                .font(.georgiaBold(16))
                                .foregroundStyle(Color.sonderTextPrimary)
                            Text(seed.country)
                                .font(.georgia(13))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        Spacer(minLength: 8)
                        if let rated {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(ScoreFormat.string(rated.cumulativeScore))
                                    .font(.georgiaBold(14))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(Color.sonderSage)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Already rated \(ScoreFormat.string(rated.cumulativeScore))")
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.sonderDivider)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.sonderSurface)
            }
        } header: {
            sectionHeader("Popular destinations")
        } footer: {
            Text("Can’t see yours? Search for any city or town in the world.")
                .font(.georgia(12))
                .foregroundStyle(Color.sonderTextSecond)
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var resultsSections: some View {
        if citySearch.isLoading && citySearch.suggestions.isEmpty {
            loadingRow("Searching…")
        }

        if !citySearch.suggestions.isEmpty {
            Section {
                ForEach(citySearch.suggestions.map(CompletionRow.init)) { row in
                    Button {
                        Task { await select(row.completion) }
                    } label: {
                        placeLabel(title: row.completion.title, subtitle: row.completion.subtitle)
                    }
                    .listRowBackground(Color.sonderSurface)
                }
            } header: {
                sectionHeader("Suggestions")
            }
        }

        if isSearchingFullQuery {
            loadingRow("Looking up places…")
        }

        if !fullSearchResults.isEmpty {
            Section {
                ForEach(fullSearchResults) { place in
                    Button {
                        selectedCity = place.makeCityData()
                    } label: {
                        placeLabel(title: place.city, subtitle: place.country)
                    }
                    .listRowBackground(Color.sonderSurface)
                }
            } header: {
                sectionHeader("Results")
            }
        }

        if let searchMessage {
            Text(searchMessage)
                .font(.georgia(14))
                .foregroundStyle(Color.sonderTextSecond)
                .listRowBackground(Color.sonderSurface)
        }

        if showsTypedFallback {
            Section {
                Button {
                    selectedCity = Attractions.makeCity(city: trimmedQuery, country: "")
                } label: {
                    Label("Use “\(trimmedQuery)”", systemImage: "plus.circle")
                        .font(.georgia(15))
                        .foregroundStyle(Color.sonderAccent)
                }
                .listRowBackground(Color.sonderSurface)
            } header: {
                sectionHeader("No matches")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.georgia(13))
            .foregroundStyle(Color.sonderTextSecond)
            .textCase(nil)
    }

    private func loadingRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(title)
                .font(.georgia(14))
                .foregroundStyle(Color.sonderTextSecond)
        }
        .listRowBackground(Color.sonderSurface)
    }

    private func placeLabel(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Color.sonderAccent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.georgiaBold(16))
                    .foregroundStyle(Color.sonderTextPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func select(_ completion: MKLocalSearchCompletion) async {
        guard !isResolving else { return }
        isResolving = true
        defer { isResolving = false }
        if let place = await CitySearchCompleterService.resolve(completion) {
            selectedCity = place.makeCityData()
        } else {
            // Couldn't resolve the suggestion (often offline): fall back to its text.
            let country = completion.subtitle.split(separator: ",").last
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            selectedCity = Attractions.makeCity(city: completion.title, country: country)
        }
    }

    private func runFullSearch() async {
        let text = trimmedQuery
        guard !text.isEmpty, !isSearchingFullQuery else { return }
        isSearchingFullQuery = true
        searchMessage = nil
        let places = await CitySearchCompleterService.search(query: text)
        isSearchingFullQuery = false
        // Ignore results for a query the user has since changed.
        guard text == trimmedQuery else { return }
        fullSearchResults = places
        if places.isEmpty && citySearch.suggestions.isEmpty {
            searchMessage = "No places found for “\(text)”."
        }
    }
}

/// Stable identity for `MKLocalSearchCompletion` rows.
private struct CompletionRow: Identifiable {
    let id: String
    let completion: MKLocalSearchCompletion

    init(_ completion: MKLocalSearchCompletion) {
        self.completion = completion
        self.id = "\(completion.title)|\(completion.subtitle)"
    }
}
