import Foundation
import CoreLocation

/// Hand-curated cities with suggested places. Any other city in the world can still be added;
/// these just get a head start with a photo, coordinates and popular places to rank.
enum Attractions {
    static let tokyo = CityData(
        city: "Tokyo",
        country: "Japan",
        flag: "🇯🇵",
        photoURL: "https://images.unsplash.com/photo-1540959733332-eab4deabeeaf?w=1200",
        latitude: 35.6762,
        longitude: 139.6503,
        attractions: [
            Attraction(name: "Senso-ji Temple", category: .culture),
            Attraction(name: "Shibuya Crossing", category: .landmark),
            Attraction(name: "Shinjuku Gyoen", category: .nature),
            Attraction(name: "Tsukiji Outer Market", category: .food),
            Attraction(name: "Yanaka Neighbourhood", category: .neighbourhood),
            Attraction(name: "teamLab Planets", category: .experience),
            Attraction(name: "Harajuku & Takeshita Street", category: .neighbourhood),
            Attraction(name: "Tokyo Skytree", category: .landmark),
            Attraction(name: "Depachika Food Halls", category: .food)
        ]
    )

    static let paris = CityData(
        city: "Paris",
        country: "France",
        flag: "🇫🇷",
        photoURL: "https://images.unsplash.com/photo-1502602898657-3e91760cbb34?w=1200",
        latitude: 48.8566,
        longitude: 2.3522,
        attractions: [
            Attraction(name: "Louvre Museum", category: .culture),
            Attraction(name: "Eiffel Tower", category: .landmark),
            Attraction(name: "Luxembourg Gardens", category: .nature),
            Attraction(name: "Marché des Enfants Rouges", category: .food),
            Attraction(name: "Le Marais", category: .neighbourhood),
            Attraction(name: "Seine River Cruise", category: .experience),
            Attraction(name: "Montmartre", category: .neighbourhood),
            Attraction(name: "Arc de Triomphe", category: .landmark),
            Attraction(name: "Parisian Cafés", category: .food)
        ]
    )

    static let lisbon = CityData(
        city: "Lisbon",
        country: "Portugal",
        flag: "🇵🇹",
        photoURL: "https://images.unsplash.com/photo-1585208798174-6cedd86e019a?w=1200",
        latitude: 38.7223,
        longitude: -9.1393,
        attractions: [
            Attraction(name: "Museu Calouste Gulbenkian", category: .culture),
            Attraction(name: "Belém Tower", category: .landmark),
            Attraction(name: "Estufa Fria", category: .nature),
            Attraction(name: "Time Out Market", category: .food),
            Attraction(name: "Alfama", category: .neighbourhood),
            Attraction(name: "Tram 28", category: .experience),
            Attraction(name: "Bairro Alto", category: .neighbourhood),
            Attraction(name: "Miradouro da Senhora do Monte", category: .landmark),
            Attraction(name: "Pastéis de Belém", category: .food)
        ]
    )

    static let newYork = CityData(
        city: "New York",
        country: "United States",
        flag: "🇺🇸",
        photoURL: "https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=1200",
        latitude: 40.7128,
        longitude: -74.0060,
        attractions: [
            Attraction(name: "The Met", category: .culture),
            Attraction(name: "Statue of Liberty", category: .landmark),
            Attraction(name: "Central Park", category: .nature),
            Attraction(name: "Chelsea Market", category: .food),
            Attraction(name: "West Village", category: .neighbourhood),
            Attraction(name: "Broadway Show", category: .experience),
            Attraction(name: "Brooklyn Bridge & DUMBO", category: .neighbourhood),
            Attraction(name: "Top of the Rock", category: .landmark),
            Attraction(name: "Pizza & Bagels", category: .food)
        ]
    )

    static let bali = CityData(
        city: "Bali",
        country: "Indonesia",
        flag: "🇮🇩",
        photoURL: "https://images.unsplash.com/photo-1537996194471-e657df975ab4?w=1200",
        latitude: -8.4095,
        longitude: 115.1889,
        attractions: [
            Attraction(name: "Ubud Art Scene", category: .culture),
            Attraction(name: "Tanah Lot", category: .landmark),
            Attraction(name: "Tegallalang Rice Terraces", category: .nature),
            Attraction(name: "Ubud Market", category: .food),
            Attraction(name: "Canggu", category: .neighbourhood),
            Attraction(name: "Balinese Cooking Class", category: .experience),
            Attraction(name: "Seminyak", category: .neighbourhood),
            Attraction(name: "Uluwatu Temple", category: .landmark),
            Attraction(name: "Warungs (Local Eateries)", category: .food)
        ]
    )

    static let kyoto = CityData(
        city: "Kyoto",
        country: "Japan",
        flag: "🇯🇵",
        photoURL: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=1200",
        latitude: 35.0116,
        longitude: 135.7681,
        attractions: [
            Attraction(name: "Fushimi Inari Taisha", category: .culture),
            Attraction(name: "Kinkaku-ji", category: .landmark),
            Attraction(name: "Arashiyama Bamboo Grove", category: .nature),
            Attraction(name: "Nishiki Market", category: .food),
            Attraction(name: "Gion", category: .neighbourhood),
            Attraction(name: "Tea Ceremony", category: .experience),
            Attraction(name: "Higashiyama", category: .neighbourhood),
            Attraction(name: "Kiyomizu-dera", category: .landmark),
            Attraction(name: "Kaiseki Dining", category: .food)
        ]
    )

    static let marrakech = CityData(
        city: "Marrakech",
        country: "Morocco",
        flag: "🇲🇦",
        photoURL: "https://images.unsplash.com/photo-1489749798305-4fea3ae63d43?w=1200",
        latitude: 31.6295,
        longitude: -7.9811,
        attractions: [
            Attraction(name: "Bahia Palace", category: .culture),
            Attraction(name: "Koutoubia Mosque", category: .landmark),
            Attraction(name: "Majorelle Garden", category: .nature),
            Attraction(name: "Jemaa el-Fnaa Food Stalls", category: .food),
            Attraction(name: "Medina Souks", category: .neighbourhood),
            Attraction(name: "Hammam Experience", category: .experience),
            Attraction(name: "Kasbah", category: .neighbourhood),
            Attraction(name: "Saadian Tombs", category: .landmark),
            Attraction(name: "Moroccan Tagine", category: .food)
        ]
    )

    static let newOrleans = CityData(
        city: "New Orleans",
        country: "United States",
        flag: "🇺🇸",
        photoURL: "https://images.unsplash.com/photo-1605649487212-47bdab064df7?w=1200",
        latitude: 29.9511,
        longitude: -90.0715,
        attractions: [
            Attraction(name: "New Orleans Museum of Art", category: .culture),
            Attraction(name: "Jackson Square", category: .landmark),
            Attraction(name: "City Park", category: .nature),
            Attraction(name: "French Market", category: .food),
            Attraction(name: "French Quarter", category: .neighbourhood),
            Attraction(name: "Live Jazz on Frenchmen Street", category: .experience),
            Attraction(name: "Garden District", category: .neighbourhood),
            Attraction(name: "St. Louis Cathedral", category: .landmark),
            Attraction(name: "Beignets & Po’boys", category: .food)
        ]
    )

    static let allCities: [CityData] = [tokyo, paris, lisbon, newYork, bali, kyoto, marrakech, newOrleans]

    /// The curated city matching a name (and flag, when known), if any.
    static func seed(city: String, flag: String = "") -> CityData? {
        let key = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCities.first { seed in
            guard seed.city.lowercased() == key else { return false }
            return flag.isEmpty || seed.flag == flag
        }
    }

    /// Builds the city a user is about to rate. Curated cities bring their photo, coordinates
    /// and suggested places; every other city starts blank and is filled in from search.
    static func makeCity(
        city: String,
        country: String,
        isoCountryCode: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) -> CityData {
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        let flag = isoCountryCode.map(flagEmoji(isoCountryCode:)) ?? ""

        if let seed = seed(city: trimmedCity, flag: flag) {
            return CityData(
                city: seed.city,
                country: seed.country,
                flag: seed.flag,
                photoURL: seed.photoURL,
                latitude: seed.latitude,
                longitude: seed.longitude,
                attractions: seed.attractions
            )
        }

        return CityData(
            city: trimmedCity.isEmpty ? "Unknown city" : trimmedCity,
            country: trimmedCountry,
            flag: flag,
            photoURL: "",
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            attractions: []
        )
    }

    /// "Portugal" → 🇵🇹. Used for cities saved without a flag. Returns "" when the name is unknown.
    static func flagEmoji(countryName: String) -> String {
        let key = countryName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty, let code = countryCodesByName[key] else { return "" }
        return flagEmoji(isoCountryCode: code)
    }

    /// Lower-cased country names (English and the current locale) mapped to ISO codes.
    private static let countryCodesByName: [String: String] = {
        var table: [String: String] = [:]
        let locales = [Locale(identifier: "en_US"), Locale.current]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2 else { continue }
            for locale in locales {
                if let name = locale.localizedString(forRegionCode: code) {
                    table[name.lowercased()] = code
                }
            }
        }
        let aliases = [
            "usa": "US", "us": "US", "united states of america": "US",
            "uk": "GB", "england": "GB", "scotland": "GB", "wales": "GB",
            "south korea": "KR", "russia": "RU", "turkey": "TR", "türkiye": "TR",
            "czech republic": "CZ", "uae": "AE", "vietnam": "VN"
        ]
        for (alias, code) in aliases where table[alias] == nil {
            table[alias] = code
        }
        return table
    }()

    /// "PT" → 🇵🇹. Returns an empty string for anything that isn't a two-letter code.
    static func flagEmoji(isoCountryCode: String) -> String {
        let code = isoCountryCode.uppercased()
        guard code.count == 2, code.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return "" }
        return code.unicodeScalars
            .compactMap { UnicodeScalar(127_397 + $0.value) }
            .map { String($0) }
            .joined()
    }
}
