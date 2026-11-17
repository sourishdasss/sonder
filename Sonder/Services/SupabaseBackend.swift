import Foundation
import Supabase

/// Production backend: Supabase Auth, Postgres (via PostgREST) and Storage.
/// Table and policy definitions live in `supabase/schema.sql`.
@MainActor
final class SupabaseBackend: Backend {
    private let client: SupabaseClient?
    private static let photoBucket = "photos"

    init(url: URL?, anonKey: String) {
        if let url, !anonKey.isEmpty {
            client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: anonKey,
                options: SupabaseClientOptions(
                    auth: .init(emitLocalSessionAsInitialSession: true)
                )
            )
        } else {
            client = nil
        }
    }

    var isConfigured: Bool { client != nil }

    private func requireClient() throws -> SupabaseClient {
        guard let client else { throw BackendError.notConfigured }
        return client
    }

    private func requireUserId() async throws -> UUID {
        guard let user = await currentUser() else { throw BackendError.notSignedIn }
        return user.id
    }

    // MARK: - Auth

    func currentUser() async -> SessionUser? {
        guard let client else { return nil }
        // `session` refreshes an expired access token when a refresh token is available.
        if let session = try? await client.auth.session {
            return SessionUser(id: session.user.id, email: session.user.email)
        }
        // Offline with an expired token: the stored session is still there, so keep the person
        // signed in and let cached content show. A revoked session is cleared by the SDK.
        if let stored = client.auth.currentSession {
            return SessionUser(id: stored.user.id, email: stored.user.email)
        }
        return nil
    }

    func authStateStream() -> AsyncStream<SessionUser?> {
        guard let client else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    switch event {
                    case .signedOut, .userDeleted:
                        continuation.yield(nil)
                    case .signedIn, .tokenRefreshed, .userUpdated:
                        if let session {
                            continuation.yield(SessionUser(id: session.user.id, email: session.user.email))
                        }
                    default:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signUp(email: String, password: String, firstName: String, lastName: String) async throws -> SignUpOutcome {
        let client = try requireClient()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Names travel as auth metadata so the `handle_new_user` trigger can create the profile
        // row even when email confirmation means there is no session yet.
        var metadata: [String: AnyJSON] = [:]
        if !first.isEmpty { metadata["first_name"] = .string(first) }
        if !last.isEmpty { metadata["last_name"] = .string(last) }

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: metadata.isEmpty ? nil : metadata
        )
        guard case .session = response else {
            return .confirmationRequired
        }
        _ = try? await updateMyName(firstName: first, lastName: last)
        return .signedIn
    }

    func signIn(email: String, password: String) async throws {
        let client = try requireClient()
        _ = try await client.auth.signIn(email: email, password: password)
        try? await ensureProfileExists()
    }

    func signOut() async throws {
        let client = try requireClient()
        do {
            try await client.auth.signOut()
        } catch {
            // Always clear the local session, even if the server call fails (e.g. offline).
            try? await client.auth.signOut(scope: .local)
        }
    }

    func sendPasswordReset(email: String) async throws {
        let client = try requireClient()
        try await client.auth.resetPasswordForEmail(email)
    }

    func deleteAccount() async throws {
        let client = try requireClient()
        let userId = try await requireUserId()

        // Best effort: remove uploaded photos first (storage objects are not covered by cascades).
        let folder = userId.uuidString.lowercased()
        let bucket = client.storage.from(Self.photoBucket)
        if let files = try? await bucket.list(path: folder), !files.isEmpty {
            _ = try? await bucket.remove(paths: files.map { "\(folder)/\($0.name)" })
        }

        // `delete_user` removes the auth user; every table cascades from it.
        try await client.rpc("delete_user").execute()
        try? await client.auth.signOut(scope: .local)
    }

    // MARK: - Profile

    func fetchMyProfile() async throws -> UserSummary? {
        let client = try requireClient()
        let userId = try await requireUserId()
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id, display_name, first_name, last_name")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        if let summary = rows.first?.toUserSummary() {
            let hasRealName = !summary.firstName.isEmpty || !summary.lastName.isEmpty
                || !["", "traveler", "traveller"].contains(summary.displayName.lowercased())
            if hasRealName { return summary }
        }
        // The row is missing or still a placeholder: fall back to the names captured at sign-up.
        let names = try await metadataNames()
        if !names.first.isEmpty || !names.last.isEmpty {
            return try await updateMyName(firstName: names.first, lastName: names.last)
        }
        return rows.first?.toUserSummary() ?? UserSummary(id: userId, displayName: "Traveller")
    }

    @discardableResult
    func updateMyName(firstName: String, lastName: String) async throws -> UserSummary {
        let client = try requireClient()
        let userId = try await requireUserId()
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let row = ProfileRow(
            id: userId,
            displayName: display.isEmpty ? "Traveller" : display,
            firstName: first,
            lastName: last
        )
        try await client.from("profiles").upsert(row, returning: .minimal).execute()

        // Keep auth metadata and past feed posts in step with the new name (non-critical).
        _ = try? await client.auth.update(user: UserAttributes(data: [
            "first_name": .string(first),
            "last_name": .string(last)
        ]))
        _ = try? await client
            .from("feed_activities")
            .update(["display_name": row.displayName ?? "Traveller"], returning: .minimal)
            .eq("user_id", value: userId.uuidString)
            .execute()
        return row.toUserSummary()
    }

    private func metadataNames() async throws -> (first: String, last: String) {
        let client = try requireClient()
        let metadata = try await client.auth.session.user.userMetadata
        func string(_ key: String) -> String {
            if case .string(let value)? = metadata[key] {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }
        return (string("first_name"), string("last_name"))
    }

    /// Guarantees a `profiles` row exists (older accounts may predate the sign-up trigger).
    private func ensureProfileExists() async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id, display_name, first_name, last_name")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard rows.isEmpty else { return }
        let names = try await metadataNames()
        try await updateMyName(firstName: names.first, lastName: names.last)
    }

    // MARK: - Rated cities

    func fetchRatedCities(userId: UUID?) async throws -> [RatedCity] {
        let client = try requireClient()
        let ownerId: UUID
        if let userId {
            ownerId = userId
        } else {
            ownerId = try await requireUserId()
        }
        let rows: [RatedCityRow] = try await client
            .from("rated_cities")
            .select()
            .eq("user_id", value: ownerId.uuidString)
            .order("cumulative_score", ascending: false)
            .execute()
            .value
        return rows.map { $0.toRatedCity() }
    }

    func saveRatedCity(_ city: RatedCity) async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        let row = RatedCityRow.from(city, userId: userId)
        try await client
            .from("rated_cities")
            .upsert(row, onConflict: "user_id,city_name,country", returning: .minimal)
            .execute()
    }

    func deleteRatedCity(id: UUID) async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        try await client
            .from("rated_cities")
            .delete(returning: .minimal)
            .eq("id", value: id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Travel profile

    func fetchTravelProfile(userId: UUID?) async throws -> TravelProfile? {
        let client = try requireClient()
        let ownerId: UUID
        if let userId {
            ownerId = userId
        } else {
            ownerId = try await requireUserId()
        }
        let rows: [TravelProfileRow] = try await client
            .from("travel_profiles")
            .select("user_id, personality_type, personality_description, taste_traits, recommendations")
            .eq("user_id", value: ownerId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.toTravelProfile()
    }

    func saveTravelProfile(_ profile: TravelProfile) async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        try await client
            .from("travel_profiles")
            .upsert(TravelProfileRow.from(profile, userId: userId), returning: .minimal)
            .execute()
    }

    // MARK: - Community places

    func fetchCityAttractions(city: String, country: String) async throws -> [Attraction] {
        let client = try requireClient()
        let rows: [CityAttractionRow] = try await client
            .from("city_attractions")
            .select("id, city_name, country, name, category, added_by")
            .eq("city_name", value: city)
            .eq("country", value: country)
            .order("created_at", ascending: true)
            .limit(60)
            .execute()
            .value
        return rows.compactMap { $0.toAttraction() }
    }

    func addCityAttraction(city: String, country: String, name: String, category: AttractionCategory) async throws -> Attraction {
        let client = try requireClient()
        let userId = try await requireUserId()
        let row = CityAttractionRow(
            id: UUID(),
            cityName: city,
            country: country,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.rawValue,
            addedBy: userId
        )
        // Someone may already have added the same place; duplicates are ignored server-side.
        try await client
            .from("city_attractions")
            .upsert(row, onConflict: "city_name,country,name", returning: .minimal, ignoreDuplicates: true)
            .execute()
        return Attraction(id: row.id, name: row.name, category: category)
    }

    // MARK: - Feed

    func fetchFeed(scope: FeedScope, limit: Int) async throws -> [FeedItem] {
        let client = try requireClient()
        var query = client.from("feed_activities").select()

        switch scope {
        case .everyone:
            break
        case .following:
            let ids = try await followingIds()
            guard !ids.isEmpty else { return [] }
            query = query.in("user_id", values: ids.map(\.uuidString))
        case .trending:
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            query = query.gte("created_at", value: ISO8601DateFormatter().string(from: weekAgo))
        }

        let rows: [FeedActivityRow] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map { $0.toFeedItem() }
    }

    func postFeedActivity(_ draft: FeedActivityDraft) async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        let profile = try? await fetchMyProfile()
        let row = FeedActivityRow(
            id: UUID(),
            userId: userId,
            ratedCityId: draft.ratedCityId,
            displayName: profile?.name ?? "Traveller",
            activityType: "visited_city",
            city: draft.city,
            country: draft.country,
            cityPhotoUrl: draft.cityPhotoURL,
            score: draft.score,
            review: draft.review,
            data: ["place_count": String(draft.placeCount)],
            createdAt: nil
        )
        try await client.from("feed_activities").insert(row, returning: .minimal).execute()
    }

    // MARK: - Social graph

    func searchUsers(query: String) async throws -> [UserSummary] {
        let client = try requireClient()
        let userId = try await requireUserId()
        // Keep the pattern to plain words so it can't alter the filter expression.
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-'’"))
        let cleaned = String(query.unicodeScalars.filter { allowed.contains($0) })
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.count >= 2 else { return [] }

        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id, display_name, first_name, last_name")
            .ilike("display_name", pattern: "%\(cleaned)%")
            .neq("id", value: userId.uuidString)
            .order("display_name", ascending: true)
            .limit(25)
            .execute()
            .value
        return rows.map { $0.toUserSummary() }
    }

    func suggestedUsers(limit: Int) async throws -> [UserSummary] {
        let client = try requireClient()
        let userId = try await requireUserId()
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id, display_name, first_name, last_name")
            .neq("id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return rows.map { $0.toUserSummary() }
    }

    func followingIds() async throws -> Set<UUID> {
        let client = try requireClient()
        let userId = try await requireUserId()
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("follower_id, following_id")
            .eq("follower_id", value: userId.uuidString)
            .execute()
            .value
        return Set(rows.map(\.followingId))
    }

    func followCounts(userId: UUID) async throws -> FollowCounts {
        let client = try requireClient()
        async let followers = client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("following_id", value: userId.uuidString)
            .execute()
            .count
        async let following = client
            .from("follows")
            .select("*", head: true, count: .exact)
            .eq("follower_id", value: userId.uuidString)
            .execute()
            .count
        return try await FollowCounts(followers: followers ?? 0, following: following ?? 0)
    }

    func followers(of userId: UUID) async throws -> [UserSummary] {
        let client = try requireClient()
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("follower_id, following_id")
            .eq("following_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
        return try await profiles(for: rows.map(\.followerId))
    }

    func following(of userId: UUID) async throws -> [UserSummary] {
        let client = try requireClient()
        let rows: [FollowRow] = try await client
            .from("follows")
            .select("follower_id, following_id")
            .eq("follower_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(200)
            .execute()
            .value
        return try await profiles(for: rows.map(\.followingId))
    }

    /// Loads profiles for `ids`, preserving their order.
    private func profiles(for ids: [UUID]) async throws -> [UserSummary] {
        guard !ids.isEmpty else { return [] }
        let client = try requireClient()
        let rows: [ProfileRow] = try await client
            .from("profiles")
            .select("id, display_name, first_name, last_name")
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
        let byId = Dictionary(rows.map { ($0.id, $0.toUserSummary()) }, uniquingKeysWith: { a, _ in a })
        return ids.compactMap { byId[$0] }
    }

    func follow(userId: UUID) async throws {
        let client = try requireClient()
        let me = try await requireUserId()
        guard me != userId else { return }
        try await client
            .from("follows")
            .upsert(
                FollowRow(followerId: me, followingId: userId),
                onConflict: "follower_id,following_id",
                returning: .minimal,
                ignoreDuplicates: true
            )
            .execute()
    }

    func unfollow(userId: UUID) async throws {
        let client = try requireClient()
        let me = try await requireUserId()
        try await client
            .from("follows")
            .delete(returning: .minimal)
            .eq("follower_id", value: me.uuidString)
            .eq("following_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Photo pins

    func fetchPhotoPins(userId: UUID?) async throws -> [PhotoPin] {
        let client = try requireClient()
        let ownerId: UUID
        if let userId {
            ownerId = userId
        } else {
            ownerId = try await requireUserId()
        }
        let rows: [PhotoPinRow] = try await client
            .from("photo_pins")
            .select()
            .eq("user_id", value: ownerId.uuidString)
            .order("uploaded_at", ascending: false)
            .limit(500)
            .execute()
            .value
        return rows.map { $0.toPhotoPin() }
    }

    func addPhotoPin(_ draft: PhotoPinDraft) async throws -> PhotoPin {
        let client = try requireClient()
        let userId = try await requireUserId()
        let pinId = UUID()
        // Storage policies compare the folder name with auth.uid()::text, which is lowercase.
        let path = "\(userId.uuidString.lowercased())/\(pinId.uuidString.lowercased()).jpg"
        let bucket = client.storage.from(Self.photoBucket)

        try await bucket.upload(path, data: draft.imageData, options: FileOptions(contentType: "image/jpeg"))
        let publicURL = try bucket.getPublicURL(path: path)

        let row = PhotoPinRow(
            id: pinId,
            userId: userId,
            photoUrl: publicURL.absoluteString,
            storagePath: path,
            latitude: draft.latitude,
            longitude: draft.longitude,
            locationName: draft.locationName,
            caption: draft.caption,
            takenAt: draft.takenAt,
            uploadedAt: nil
        )
        do {
            try await client.from("photo_pins").insert(row, returning: .minimal).execute()
        } catch {
            // Don't leave an orphaned file behind if the row can't be written.
            _ = try? await bucket.remove(paths: [path])
            throw error
        }
        return row.toPhotoPin()
    }

    func deletePhotoPin(_ pin: PhotoPin) async throws {
        let client = try requireClient()
        let userId = try await requireUserId()
        try await client
            .from("photo_pins")
            .delete(returning: .minimal)
            .eq("id", value: pin.id.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        if let path = pin.storagePath {
            _ = try? await client.storage.from(Self.photoBucket).remove(paths: [path])
        }
    }
}
