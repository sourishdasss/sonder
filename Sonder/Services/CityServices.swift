import CoreLocation
import Foundation

/// Finds a representative photo for any city, without an API key.
///
/// Curated cities ship with a photo. For everything else this asks Wikipedia for the lead image
/// of the best-matching article and remembers the answer.
actor CityPhotoService {
    static let shared = CityPhotoService()

    private var memory: [String: String] = [:]
    private let defaults = UserDefaults.standard
    private let defaultsKey = "sonder.cityPhotoURLs"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        memory = (UserDefaults.standard.dictionary(forKey: "sonder.cityPhotoURLs") as? [String: String]) ?? [:]
    }

    /// Returns a photo URL string for the city, or nil when none can be found.
    func photoURL(city: String, country: String) async -> String? {
        let key = CityData.placeKey(city: city, country: country)
        if let seed = Attractions.seed(city: city), !seed.photoURL.isEmpty,
           country.isEmpty || seed.country.lowercased() == country.lowercased() {
            return seed.photoURL
        }
        if let cached = memory[key] {
            return cached.isEmpty ? nil : cached
        }

        let found = await lookUp(query: [city, country].filter { !$0.isEmpty }.joined(separator: " "))
        if let found {
            memory[key] = found
            defaults.set(memory, forKey: defaultsKey)
        }
        return found
    }

    private struct WikiResponse: Decodable {
        struct Query: Decodable {
            let pages: [String: Page]
        }
        struct Page: Decodable {
            struct Thumbnail: Decodable { let source: String }
            let thumbnail: Thumbnail?
        }
        let query: Query?
    }

    private func lookUp(query: String) async -> String? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "1200"),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query),
            URLQueryItem(name: "gsrlimit", value: "1")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Sonder-iOS/1.0", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(WikiResponse.self, from: data) else { return nil }
        return decoded.query?.pages.values.compactMap { $0.thumbnail?.source }.first
    }
}

/// Resolves city coordinates for the map, caching results on disk so each city is geocoded once.
@MainActor
final class CityGeocoder {
    static let shared = CityGeocoder()

    private var cache: [String: [Double]]
    private let defaultsKey = "sonder.cityCoordinates"
    private let geocoder = CLGeocoder()

    private init() {
        cache = (UserDefaults.standard.dictionary(forKey: "sonder.cityCoordinates") as? [String: [Double]]) ?? [:]
    }

    func cachedCoordinate(for city: CityData) -> CLLocationCoordinate2D? {
        if let coordinate = city.coordinate { return coordinate }
        guard let pair = cache[city.placeKey], pair.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
    }

    func remember(_ coordinate: CLLocationCoordinate2D, for city: CityData) {
        cache[city.placeKey] = [coordinate.latitude, coordinate.longitude]
        UserDefaults.standard.set(cache, forKey: defaultsKey)
    }

    /// Coordinate for a city: stored value, then the cache, then a geocoder lookup.
    func coordinate(for city: CityData) async -> CLLocationCoordinate2D? {
        if let known = cachedCoordinate(for: city) { return known }
        let name = city.city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let query = [name, city.country].filter { !$0.isEmpty }.joined(separator: ", ")
        guard let placemarks = try? await geocoder.geocodeAddressString(query),
              let coordinate = placemarks.first?.location?.coordinate else { return nil }
        remember(coordinate, for: city)
        return coordinate
    }

    /// "Lisbon, Portugal" for a coordinate, used to label photo pins.
    func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.locality ?? placemark.administrativeArea, placemark.country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
