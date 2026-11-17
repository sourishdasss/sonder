import Foundation

/// Small on-disk cache of the signed-in user's own data, so the app opens instantly and still
/// shows something useful offline. Stored in Caches (the system may purge it; the server is the
/// source of truth) and keyed by user id so accounts never see each other's data.
struct LocalCache {
    struct Snapshot: Codable {
        var cities: [RatedCityRow]
        var travelProfile: TravelProfileRow?
    }

    private let directory: URL?

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("SonderUserData", isDirectory: true)) {
        self.directory = directory
    }

    private func fileURL(for userId: UUID) -> URL? {
        directory?.appendingPathComponent("\(userId.uuidString.lowercased()).json")
    }

    func load(userId: UUID) -> (cities: [RatedCity], travelProfile: TravelProfile?)? {
        guard let url = fileURL(for: userId),
              let data = try? Data(contentsOf: url),
              let snapshot = try? Self.decoder.decode(Snapshot.self, from: data) else { return nil }
        return (snapshot.cities.map { $0.toRatedCity() }, snapshot.travelProfile?.toTravelProfile())
    }

    func save(cities: [RatedCity], travelProfile: TravelProfile?, userId: UUID) {
        guard let directory, let url = fileURL(for: userId) else { return }
        let snapshot = Snapshot(
            cities: cities.map { city in
                // Keep the creation date, which the upload row intentionally leaves to the server.
                let row = RatedCityRow.from(city, userId: userId)
                return RatedCityRow(
                    id: row.id, userId: row.userId, cityName: row.cityName, country: row.country,
                    flag: row.flag, photoUrl: row.photoUrl, latitude: row.latitude, longitude: row.longitude,
                    cumulativeScore: row.cumulativeScore, summary: row.summary, highlight: row.highlight,
                    wouldRecommendIf: row.wouldRecommendIf, scoreBreakdown: row.scoreBreakdown,
                    topAttractionName: row.topAttractionName, ratings: row.ratings, createdAt: city.createdAt
                )
            },
            travelProfile: travelProfile.flatMap { $0.isPlaceholder ? nil : TravelProfileRow.from($0, userId: userId) }
        )
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // The cache is an optimisation; failing to write it is not worth surfacing.
        }
    }

    func clear(userId: UUID) {
        guard let url = fileURL(for: userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
