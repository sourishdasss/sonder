import Foundation

/// The signed-in account.
struct SessionUser: Equatable, Sendable {
    let id: UUID
    let email: String?
}

enum SignUpOutcome: Equatable, Sendable {
    /// The account was created and a session is active.
    case signedIn
    /// The account was created but the email address must be confirmed before signing in.
    case confirmationRequired
}

enum BackendError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sonder isn’t connected to a server. Check the Supabase settings in Config/Sonder.xcconfig."
        case .notSignedIn:
            return "Please sign in again to continue."
        case .message(let text):
            return text
        }
    }
}

/// Everything the app needs from a server. `SupabaseBackend` is the production implementation;
/// `InMemoryBackend` backs demo mode, previews and tests.
@MainActor
protocol Backend: AnyObject {
    var isConfigured: Bool { get }

    // MARK: Auth
    func currentUser() async -> SessionUser?
    /// Emits the signed-in user whenever the session changes, and `nil` on sign-out or expiry.
    func authStateStream() -> AsyncStream<SessionUser?>
    func signUp(email: String, password: String, firstName: String, lastName: String) async throws -> SignUpOutcome
    func signIn(email: String, password: String) async throws
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
    /// Permanently deletes the account and everything it owns.
    func deleteAccount() async throws

    // MARK: Profile
    func fetchMyProfile() async throws -> UserSummary?
    @discardableResult
    func updateMyName(firstName: String, lastName: String) async throws -> UserSummary

    // MARK: Rated cities
    /// - Parameter userId: `nil` for the signed-in user.
    func fetchRatedCities(userId: UUID?) async throws -> [RatedCity]
    func saveRatedCity(_ city: RatedCity) async throws
    func deleteRatedCity(id: UUID) async throws

    // MARK: Travel profile
    func fetchTravelProfile(userId: UUID?) async throws -> TravelProfile?
    func saveTravelProfile(_ profile: TravelProfile) async throws

    // MARK: Community places
    func fetchCityAttractions(city: String, country: String) async throws -> [Attraction]
    func addCityAttraction(city: String, country: String, name: String, category: AttractionCategory) async throws -> Attraction

    // MARK: Feed
    func fetchFeed(scope: FeedScope, limit: Int) async throws -> [FeedItem]
    func postFeedActivity(_ draft: FeedActivityDraft) async throws

    // MARK: Social graph
    func searchUsers(query: String) async throws -> [UserSummary]
    func suggestedUsers(limit: Int) async throws -> [UserSummary]
    func followingIds() async throws -> Set<UUID>
    func followCounts(userId: UUID) async throws -> FollowCounts
    func followers(of userId: UUID) async throws -> [UserSummary]
    func following(of userId: UUID) async throws -> [UserSummary]
    func follow(userId: UUID) async throws
    func unfollow(userId: UUID) async throws

    // MARK: Photo pins
    func fetchPhotoPins(userId: UUID?) async throws -> [PhotoPin]
    func addPhotoPin(_ draft: PhotoPinDraft) async throws -> PhotoPin
    func deletePhotoPin(_ pin: PhotoPin) async throws
}

/// Chooses the backend for this launch.
@MainActor
enum BackendProvider {
    static let shared: Backend = make()

    private static func make() -> Backend {
        #if DEBUG
        if Config.isDemoMode {
            return InMemoryBackend.demo()
        }
        #endif
        return SupabaseBackend(url: Config.supabaseURL, anonKey: Config.supabaseAnonKey)
    }
}

/// Turns low-level errors into copy that is safe to show a person.
enum ErrorCopy {
    static func message(for error: Error) -> String {
        if let backend = error as? BackendError, let text = backend.errorDescription {
            return text
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You’re offline. Check your connection and try again."
            case .timedOut:
                return "That took too long. Please try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn’t reach the Sonder server. Please try again in a moment."
            default:
                return "A network problem got in the way. Please try again."
            }
        }

        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") {
            return "That email and password don’t match. Please try again."
        }
        if lower.contains("email not confirmed") {
            return "Please confirm your email address first — check your inbox for the link."
        }
        if lower.contains("already registered") || lower.contains("already been registered") {
            return "An account with that email already exists. Try signing in instead."
        }
        if lower.contains("rate limit") || lower.contains("too many requests") {
            return "Too many attempts. Please wait a minute and try again."
        }
        if lower.contains("password should be") || lower.contains("weak password") {
            return "Please choose a stronger password (at least 8 characters)."
        }
        if lower.contains("unable to validate email") || lower.contains("invalid email") {
            return "That doesn’t look like a valid email address."
        }
        if lower.contains("row-level security") || lower.contains("permission denied") {
            return "You don’t have permission to do that."
        }
        if lower.contains("could not find the table") || lower.contains("does not exist")
            || lower.contains("schema cache") {
            return "The Sonder server is missing part of its setup. Apply supabase/schema.sql to the project."
        }
        if lower.contains("offline") || lower.contains("internet connection") || lower.contains("hostname could not be found") {
            return "Couldn’t reach the Sonder server. Check your connection and try again."
        }
        return raw.isEmpty ? "Something went wrong. Please try again." : raw
    }
}
