import Foundation

// Codable row types mirroring the Postgres tables in supabase/schema.sql.
// Optional properties are omitted from inserts when nil, so database defaults apply.

struct ProfileRow: Codable, Sendable {
    let id: UUID
    var displayName: String?
    var firstName: String?
    var lastName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case firstName = "first_name"
        case lastName = "last_name"
    }

    func toUserSummary() -> UserSummary {
        UserSummary(
            id: id,
            displayName: displayName ?? "",
            firstName: firstName ?? "",
            lastName: lastName ?? ""
        )
    }
}

struct RatedCityRow: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let cityName: String
    let country: String
    let flag: String
    let photoUrl: String
    let latitude: Double?
    let longitude: Double?
    let cumulativeScore: Double
    let summary: String
    let highlight: String
    let wouldRecommendIf: String
    let scoreBreakdown: [String: Double]?
    let topAttractionName: String?
    let ratings: [AttractionRatingDTO]
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case cityName = "city_name"
        case country
        case flag
        case photoUrl = "photo_url"
        case latitude
        case longitude
        case cumulativeScore = "cumulative_score"
        case summary
        case highlight
        case wouldRecommendIf = "would_recommend_if"
        case scoreBreakdown = "score_breakdown"
        case topAttractionName = "top_attraction_name"
        case ratings
        case createdAt = "created_at"
    }

    func toRatedCity() -> RatedCity {
        let seed = Attractions.seed(city: cityName, flag: flag)
        let attractions: [Attraction] = ratings.compactMap { dto in
            guard let id = UUID(uuidString: dto.attractionId),
                  let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  let rawCategory = dto.category,
                  let category = AttractionCategory(rawValue: rawCategory) else { return nil }
            return Attraction(id: id, name: name, category: category)
        }
        // Rows written by the first version of the app have no flag and point at Unsplash Source,
        // which has been shut down. Treat those links as missing so a real photo is looked up.
        let storedPhoto = photoUrl.contains("source.unsplash.com") ? "" : photoUrl
        let cityData = CityData(
            id: id,
            city: cityName,
            country: country,
            flag: flag.isEmpty ? (seed?.flag ?? Attractions.flagEmoji(countryName: country)) : flag,
            photoURL: storedPhoto.isEmpty ? (seed?.photoURL ?? "") : storedPhoto,
            latitude: latitude ?? seed?.latitude,
            longitude: longitude ?? seed?.longitude,
            attractions: attractions
        )
        return RatedCity(
            id: id,
            cityData: cityData,
            cumulativeScore: cumulativeScore,
            summary: summary,
            highlight: highlight,
            wouldRecommendIf: wouldRecommendIf,
            scoreBreakdown: scoreBreakdown,
            ratings: ratings.compactMap { $0.toAttractionRating() },
            topAttractionName: topAttractionName,
            createdAt: createdAt
        )
    }

    static func from(_ city: RatedCity, userId: UUID) -> RatedCityRow {
        let byId = Dictionary(city.cityData.attractions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return RatedCityRow(
            id: city.id,
            userId: userId,
            cityName: city.cityData.city,
            country: city.cityData.country,
            flag: city.cityData.flag,
            photoUrl: city.cityData.photoURL,
            latitude: city.cityData.latitude,
            longitude: city.cityData.longitude,
            cumulativeScore: city.cumulativeScore,
            summary: city.summary,
            highlight: city.highlight,
            wouldRecommendIf: city.wouldRecommendIf,
            scoreBreakdown: city.scoreBreakdown,
            topAttractionName: city.topAttractionName,
            ratings: city.ratings.map { rating in
                let attraction = byId[rating.attractionId]
                return AttractionRatingDTO(
                    attractionId: rating.attractionId.uuidString,
                    name: attraction?.name,
                    category: attraction?.category.rawValue,
                    sentiment: rating.sentiment.rawValue,
                    rank: rating.rankAmongSimilar,
                    score: nil
                )
            },
            createdAt: nil
        )
    }
}

struct AttractionRatingDTO: Codable, Sendable {
    let attractionId: String
    var name: String?
    var category: String?
    var sentiment: String?
    var rank: Int?
    /// Legacy 1–5 stars from the first version of the app.
    var score: Int?

    enum CodingKeys: String, CodingKey {
        case attractionId = "attraction_id"
        case name
        case category
        case sentiment
        case rank
        case score
    }

    func toAttractionRating() -> AttractionRating? {
        guard let id = UUID(uuidString: attractionId) else { return nil }
        if let sentiment, let value = VisitSentiment(rawValue: sentiment) {
            return AttractionRating(attractionId: id, sentiment: value, rankAmongSimilar: rank ?? 1)
        }
        if let score {
            let value: VisitSentiment = score >= 4 ? .wouldReturn : (score >= 3 ? .decent : .waste)
            return AttractionRating(attractionId: id, sentiment: value, rankAmongSimilar: rank ?? 1)
        }
        return nil
    }
}

struct TravelProfileRow: Codable, Sendable {
    let userId: UUID
    let personalityType: String
    let personalityDescription: String
    let tasteTraits: [String]
    let recommendations: [RecommendationDTO]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case personalityType = "personality_type"
        case personalityDescription = "personality_description"
        case tasteTraits = "taste_traits"
        case recommendations
    }

    func toTravelProfile() -> TravelProfile {
        TravelProfile(
            personalityType: personalityType,
            personalityDescription: personalityDescription,
            tasteTraits: tasteTraits,
            recommendations: recommendations.map {
                DestinationRecommendation(
                    destination: $0.destination,
                    matchReason: $0.matchReason,
                    vibeTags: $0.vibeTags,
                    matchScore: $0.matchScore ?? 0
                )
            }
        )
    }

    static func from(_ profile: TravelProfile, userId: UUID) -> TravelProfileRow {
        TravelProfileRow(
            userId: userId,
            personalityType: profile.personalityType,
            personalityDescription: profile.personalityDescription,
            tasteTraits: profile.tasteTraits,
            recommendations: profile.recommendations.map {
                RecommendationDTO(
                    destination: $0.destination,
                    matchReason: $0.matchReason,
                    vibeTags: $0.vibeTags,
                    matchScore: $0.matchScore
                )
            }
        )
    }
}

struct RecommendationDTO: Codable, Sendable {
    let destination: String
    let matchReason: String
    let vibeTags: [String]
    var matchScore: Double?

    enum CodingKeys: String, CodingKey {
        case destination
        case matchReason = "match_reason"
        case vibeTags = "vibe_tags"
        case matchScore = "match_score"
    }
}

struct CityAttractionRow: Codable, Sendable {
    let id: UUID
    let cityName: String
    let country: String
    let name: String
    let category: String
    let addedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case cityName = "city_name"
        case country
        case name
        case category
        case addedBy = "added_by"
    }

    func toAttraction() -> Attraction? {
        guard let category = AttractionCategory(rawValue: category) else { return nil }
        return Attraction(id: id, name: name, category: category)
    }
}

struct FeedActivityRow: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let ratedCityId: UUID?
    let displayName: String
    let activityType: String
    let city: String
    let country: String
    let cityPhotoUrl: String?
    let score: Double?
    let review: String?
    let data: [String: String]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case ratedCityId = "rated_city_id"
        case displayName = "display_name"
        case activityType = "activity_type"
        case city
        case country
        case cityPhotoUrl = "city_photo_url"
        case score
        case review
        case data
        case createdAt = "created_at"
    }

    func toFeedItem() -> FeedItem {
        let payload = data ?? [:]
        let action: FeedAction
        switch activityType {
        case "rated_attraction":
            let sentiment = payload["sentiment"].flatMap(VisitSentiment.init(rawValue:))
            action = .ratedAttraction(attractionName: payload["attraction_name"] ?? "a place", sentiment: sentiment)
        case "added_favourite":
            action = .addedToFavourites
        default:
            let count = Int(payload["place_count"] ?? payload["attraction_count"] ?? "0") ?? 0
            action = .visitedCity(placeCount: count)
        }
        return FeedItem(
            id: id,
            userId: userId,
            userName: displayName,
            action: action,
            city: city,
            country: country,
            cityPhotoURL: cityPhotoUrl,
            score: score,
            review: review,
            timestamp: createdAt ?? Date()
        )
    }
}

struct FollowRow: Codable, Sendable {
    let followerId: UUID
    let followingId: UUID

    enum CodingKeys: String, CodingKey {
        case followerId = "follower_id"
        case followingId = "following_id"
    }
}

struct PhotoPinRow: Codable, Sendable {
    let id: UUID
    let userId: UUID
    let photoUrl: String
    let storagePath: String?
    let latitude: Double
    let longitude: Double
    let locationName: String?
    let caption: String?
    let takenAt: Date?
    let uploadedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case photoUrl = "photo_url"
        case storagePath = "storage_path"
        case latitude
        case longitude
        case locationName = "location_name"
        case caption
        case takenAt = "taken_at"
        case uploadedAt = "uploaded_at"
    }

    func toPhotoPin() -> PhotoPin {
        PhotoPin(
            id: id,
            userId: userId,
            photoURL: photoUrl,
            storagePath: storagePath,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            caption: caption,
            takenAt: takenAt,
            uploadedAt: uploadedAt ?? Date()
        )
    }
}
