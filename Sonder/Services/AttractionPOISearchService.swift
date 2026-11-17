import CoreLocation
import Foundation
import MapKit

/// One row in the city-scoped place search list.
struct CityPlaceSearchResult: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let category: AttractionCategory
}

/// Place search limited to the area around one city.
///
/// `MKLocalSearchCompleter` happily returns famous places on the other side of the world, so this
/// runs a regional `MKLocalSearch` and then drops anything too far from the city centre.
@MainActor
final class AttractionPOISearch: ObservableObject {
    @Published private(set) var results: [CityPlaceSearchResult] = []
    @Published private(set) var isLoading = false
    /// True once the city has been located and results are being distance-filtered.
    @Published private(set) var isCityScoped = false

    private var debounceTask: Task<Void, Never>?
    private var cityName = ""
    private var country = ""
    private var cityCenter: CLLocationCoordinate2D?
    private var searchRegion: MKCoordinateRegion?
    private var maxRadiusMeters: CLLocationDistance = 55_000

    /// Locates the city (using known coordinates when available) and scopes searches to it.
    /// Returns the city centre so callers can store it.
    @discardableResult
    func configure(for city: CityData) async -> CLLocationCoordinate2D? {
        cityName = city.city.trimmingCharacters(in: .whitespacesAndNewlines)
        country = city.country.trimmingCharacters(in: .whitespacesAndNewlines)

        if let coordinate = city.coordinate {
            let built = CitySearchRegionBuilder.region(placemark: nil, coordinate: coordinate)
            apply(center: coordinate, region: built.region, radius: built.radiusCap)
            return coordinate
        }

        let query = [cityName, country].filter { !$0.isEmpty }.joined(separator: ", ")
        guard !query.isEmpty,
              let placemark = try? await CLGeocoder().geocodeAddressString(query).first,
              let coordinate = placemark.location?.coordinate else {
            isCityScoped = false
            return nil
        }
        let built = CitySearchRegionBuilder.region(placemark: placemark, coordinate: coordinate)
        apply(center: coordinate, region: built.region, radius: built.radiusCap)
        return coordinate
    }

    private func apply(center: CLLocationCoordinate2D, region: MKCoordinateRegion, radius: CLLocationDistance) {
        cityCenter = center
        searchRegion = region
        maxRadiusMeters = max(15_000, min(radius * 1.1, 90_000))
        isCityScoped = true
    }

    func reset() {
        debounceTask?.cancel()
        debounceTask = nil
        results = []
        isLoading = false
    }

    func updateQuery(_ text: String) {
        debounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isLoading = false
            return
        }
        isLoading = true
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed)
        }
    }

    private func performSearch(_ userQuery: String) async {
        let cityLine = [cityName, country].filter { !$0.isEmpty }.joined(separator: ", ")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cityLine.isEmpty ? userQuery : "\(userQuery), \(cityLine)"
        request.resultTypes = .pointOfInterest
        if let searchRegion {
            request.region = searchRegion
        }

        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        guard !Task.isCancelled else { return }

        let origin = cityCenter.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var seen = Set<String>()
        var found: [CityPlaceSearchResult] = []
        for item in items {
            let name = (item.name ?? item.placemark.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            if let origin {
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: origin)
                guard distance <= maxRadiusMeters else { continue }
            }
            guard seen.insert(name.lowercased()).inserted else { continue }
            found.append(CityPlaceSearchResult(
                title: name,
                subtitle: Self.subtitle(for: item.placemark),
                category: Self.inferredCategory(for: item)
            ))
            if found.count >= 12 { break }
        }
        results = found
        isLoading = false
    }

    private static func subtitle(for placemark: MKPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, placemark.subLocality ?? placemark.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Best-guess category for a map item (the user can change it before rating).
    /// `MKPointOfInterestCategory` gained many cases in iOS 18, so there are two paths.
    static func inferredCategory(for item: MKMapItem) -> AttractionCategory {
        guard let category = item.pointOfInterestCategory else { return .landmark }
        if #available(iOS 18.0, *) {
            switch category {
            case .museum, .library, .university, .school, .theater, .musicVenue, .planetarium:
                return .culture
            case .nationalPark, .park, .beach, .campground, .hiking:
                return .nature
            case .restaurant, .cafe, .bakery, .brewery, .winery, .distillery, .foodMarket:
                return .food
            case .landmark, .castle, .fortress, .nationalMonument:
                return .landmark
            case .movieTheater, .nightlife, .amusementPark, .marina, .stadium, .zoo, .aquarium, .spa, .fairground:
                return .experience
            default:
                return .landmark
            }
        } else {
            switch category {
            case .museum, .library, .university, .school, .theater:
                return .culture
            case .nationalPark, .park, .beach, .campground:
                return .nature
            case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket:
                return .food
            case .movieTheater, .nightlife, .amusementPark, .marina, .stadium, .zoo, .aquarium:
                return .experience
            default:
                return .landmark
            }
        }
    }
}

// MARK: - Region helper

enum CitySearchRegionBuilder {
    /// Prefers the geocoder's circular region; otherwise a compact box around the coordinate.
    static func region(
        placemark: CLPlacemark?,
        coordinate: CLLocationCoordinate2D,
        fallbackSpanDegrees: Double = 0.38
    ) -> (region: MKCoordinateRegion, radiusCap: CLLocationDistance) {
        let cosLatitude = max(0.25, cos(coordinate.latitude * .pi / 180))
        if let circle = placemark?.region as? CLCircularRegion {
            let radius = min(max(circle.radius, 8_000), 80_000)
            let latitudeDelta = min(1.4, max(0.14, (radius * 2.4) / 111_000))
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: min(1.8, latitudeDelta / cosLatitude))
            )
            return (region, radius)
        }
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: fallbackSpanDegrees,
                longitudeDelta: min(1.8, fallbackSpanDegrees / cosLatitude)
            )
        )
        return (region, min((fallbackSpanDegrees * 111_000) / 2 * 2.2, 70_000))
    }
}
