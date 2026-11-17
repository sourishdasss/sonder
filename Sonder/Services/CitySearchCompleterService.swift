import CoreLocation
import Foundation
import MapKit

/// Maps-style city search: debounced `MKLocalSearchCompleter` suggestions, plus helpers that
/// resolve a suggestion (or free text) to a concrete city and country.
final class CitySearchCompleterService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var isLoading = false

    private let completer = MKLocalSearchCompleter()
    private var debounceTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.pointOfInterestFilter = .excludingAll
        completer.region = Self.worldRegion
    }

    private static var worldRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 360)
        )
    }

    func reset() {
        debounceTask?.cancel()
        debounceTask = nil
        completer.queryFragment = ""
        suggestions = []
        isLoading = false
    }

    func updateQueryFragment(_ text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            completer.queryFragment = ""
            isLoading = false
            return
        }
        isLoading = true
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            self?.completer.queryFragment = trimmed
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        DispatchQueue.main.async {
            self.suggestions = results
            self.isLoading = false
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.suggestions = []
            self.isLoading = false
        }
    }

    // MARK: - Resolving

    /// Turns a tapped suggestion into a city.
    @MainActor
    static func resolve(_ completion: MKLocalSearchCompletion) async -> ResolvedCityPlace? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems.lazy.compactMap(ResolvedCityPlace.init(mapItem:)).first
    }

    /// Full-text lookup for when the user presses Search on the keyboard.
    @MainActor
    static func search(query: String) async -> [ResolvedCityPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = worldRegion
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        var seen = Set<String>()
        var places: [ResolvedCityPlace] = []
        for item in response.mapItems {
            guard let place = ResolvedCityPlace(mapItem: item) else { continue }
            guard seen.insert(CityData.placeKey(city: place.city, country: place.country)).inserted else { continue }
            places.append(place)
            if places.count >= 20 { break }
        }
        return places
    }
}

/// A resolved place, ready to become a `CityData`.
struct ResolvedCityPlace: Hashable, Identifiable {
    let city: String
    let country: String
    let isoCountryCode: String?
    let coordinate: CLLocationCoordinate2D

    var id: String { CityData.placeKey(city: city, country: country) }

    static func == (lhs: ResolvedCityPlace, rhs: ResolvedCityPlace) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init?(mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        func clean(_ value: String?) -> String {
            value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let candidates = [
            clean(placemark.locality),
            clean(placemark.administrativeArea),
            clean(placemark.subAdministrativeArea),
            clean(placemark.name)
        ]
        guard let city = candidates.first(where: { !$0.isEmpty }) else { return nil }

        var country = clean(placemark.country)
        if country.isEmpty, let code = placemark.isoCountryCode {
            country = Locale.current.localizedString(forRegionCode: code) ?? code
        }

        self.city = city
        self.country = country
        self.isoCountryCode = placemark.isoCountryCode
        self.coordinate = placemark.coordinate
    }

    /// The city this place refers to, using curated data when Sonder has it.
    func makeCityData() -> CityData {
        Attractions.makeCity(
            city: city,
            country: country,
            isoCountryCode: isoCountryCode,
            coordinate: CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
        )
    }
}
