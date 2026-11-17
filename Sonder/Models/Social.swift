import Foundation
import CoreLocation

// MARK: - People

/// Public-facing summary of a Sonder user.
struct UserSummary: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var displayName: String
    var firstName: String
    var lastName: String

    init(id: UUID, displayName: String, firstName: String = "", lastName: String = "") {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
    }

    /// Best available name: "First Last", then the stored display name.
    var name: String {
        let full = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !full.isEmpty { return full }
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? "Traveller" : display
    }

    /// Up to two initials for avatar placeholders.
    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "S" : letters.joined()
    }
}

struct FollowCounts: Equatable, Sendable {
    var followers: Int
    var following: Int

    static let zero = FollowCounts(followers: 0, following: 0)
}

// MARK: - Feed

enum FeedScope: String, CaseIterable, Identifiable, Sendable {
    case everyone = "Everyone"
    case following = "Following"
    case trending = "Trending"

    var id: String { rawValue }
}

enum FeedAction: Hashable, Sendable {
    case ratedAttraction(attractionName: String, sentiment: VisitSentiment?)
    case visitedCity(placeCount: Int)
    case addedToFavourites

    var displayText: String {
        switch self {
        case .ratedAttraction(let name, let sentiment):
            if let sentiment {
                return "rated \(name) · \(sentiment.shortLabel)"
            }
            return "rated \(name)"
        case .visitedCity(let count):
            if count <= 0 { return "logged a visit" }
            return count == 1 ? "rated 1 place" : "rated \(count) places"
        case .addedToFavourites:
            return "added a favourite"
        }
    }
}

struct FeedItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let userName: String
    let action: FeedAction
    let city: String
    let country: String
    let cityPhotoURL: String?
    let score: Double?
    let review: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        userName: String,
        action: FeedAction,
        city: String,
        country: String,
        cityPhotoURL: String? = nil,
        score: Double? = nil,
        review: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.action = action
        self.city = city
        self.country = country
        self.cityPhotoURL = cityPhotoURL
        self.score = score
        self.review = review
        self.timestamp = timestamp
    }

    var author: UserSummary { UserSummary(id: userId, displayName: userName) }

    var placeName: String { country.isEmpty ? city : "\(city), \(country)" }

    var relativeTime: String {
        FeedItem.relativeFormatter.localizedString(for: timestamp, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

/// What gets written to the feed when a user logs a city.
struct FeedActivityDraft: Sendable {
    var ratedCityId: UUID?
    var city: String
    var country: String
    var cityPhotoURL: String?
    var score: Double?
    var review: String?
    var placeCount: Int
}

/// A city that several people rated recently.
struct TrendingCity: Identifiable, Hashable, Sendable {
    let city: String
    let country: String
    let photoURL: String?
    let ratingCount: Int
    let averageScore: Double

    var id: String { CityData.placeKey(city: city, country: country) }

    /// Groups recent feed activity by city, most-rated first.
    static func rank(_ items: [FeedItem], limit: Int = 12) -> [TrendingCity] {
        let groups = Dictionary(grouping: items) { CityData.placeKey(city: $0.city, country: $0.country) }
        let cities: [TrendingCity] = groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            let scores = group.compactMap(\.score)
            let average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            return TrendingCity(
                city: first.city,
                country: first.country,
                photoURL: group.compactMap(\.cityPhotoURL).first { !$0.isEmpty },
                ratingCount: group.count,
                averageScore: average
            )
        }
        return Array(
            cities.sorted { lhs, rhs in
                if lhs.ratingCount != rhs.ratingCount { return lhs.ratingCount > rhs.ratingCount }
                if lhs.averageScore != rhs.averageScore { return lhs.averageScore > rhs.averageScore }
                return lhs.city < rhs.city
            }
            .prefix(limit)
        )
    }
}

// MARK: - Photo pins

/// A location-tagged travel photo shown on the map.
struct PhotoPin: Identifiable, Hashable, Sendable {
    let id: UUID
    let userId: UUID
    let photoURL: String
    /// Storage object path, used to delete the file with the pin.
    let storagePath: String?
    let latitude: Double
    let longitude: Double
    let locationName: String?
    let caption: String?
    let takenAt: Date?
    let uploadedAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Country parsed from "City, Country" style names, for the map stats.
    var countryName: String? {
        guard let last = locationName?.split(separator: ",").last else { return nil }
        let trimmed = last.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Everything needed to create a photo pin.
struct PhotoPinDraft: Sendable {
    var imageData: Data
    var latitude: Double
    var longitude: Double
    var locationName: String?
    var caption: String?
    var takenAt: Date?
}
