import Foundation
import SwiftUI

/// The follow graph and other people's public travel data.
@MainActor
final class SocialStore: ObservableObject {
    @Published private(set) var followingIds: Set<UUID> = []
    @Published private(set) var myCounts: FollowCounts = .zero
    /// Users with a follow/unfollow request in flight (their buttons show progress).
    @Published private(set) var pending: Set<UUID> = []

    private let backend: Backend
    private let toaster: Toaster
    private(set) var userId: UUID?

    init(backend: Backend, toaster: Toaster? = nil) {
        self.backend = backend
        self.toaster = toaster ?? .shared
    }

    func start(userId: UUID) async {
        guard self.userId != userId else { return }
        reset()
        self.userId = userId
        await refresh()
    }

    func reset() {
        userId = nil
        followingIds = []
        myCounts = .zero
        pending = []
    }

    /// Reloads who the user follows and their own counts. Failures are silent: the social graph
    /// is secondary, and screens that depend on it show their own errors.
    func refresh() async {
        guard let userId else { return }
        if let ids = try? await backend.followingIds() {
            followingIds = ids
        }
        if let counts = try? await backend.followCounts(userId: userId) {
            myCounts = counts
        }
    }

    func isMe(_ id: UUID) -> Bool { id == userId }

    func isFollowing(_ id: UUID) -> Bool { followingIds.contains(id) }

    /// Follows or unfollows optimistically, rolling back if the server rejects the change.
    func toggleFollow(_ user: UserSummary) async {
        guard !isMe(user.id), !pending.contains(user.id) else { return }
        let wasFollowing = isFollowing(user.id)
        pending.insert(user.id)
        defer { pending.remove(user.id) }

        if wasFollowing {
            followingIds.remove(user.id)
            myCounts.following = max(0, myCounts.following - 1)
        } else {
            followingIds.insert(user.id)
            myCounts.following += 1
        }

        do {
            if wasFollowing {
                try await backend.unfollow(userId: user.id)
            } else {
                try await backend.follow(userId: user.id)
            }
        } catch {
            if wasFollowing {
                followingIds.insert(user.id)
                myCounts.following += 1
            } else {
                followingIds.remove(user.id)
                myCounts.following = max(0, myCounts.following - 1)
            }
            toaster.error(error)
        }
    }

    // MARK: - Lookups (thin pass-throughs so views never talk to the backend directly)

    func search(_ query: String) async throws -> [UserSummary] {
        try await backend.searchUsers(query: query)
    }

    func suggestedUsers() async throws -> [UserSummary] {
        try await backend.suggestedUsers(limit: 20)
    }

    func counts(for userId: UUID) async throws -> FollowCounts {
        try await backend.followCounts(userId: userId)
    }

    func followers(of userId: UUID) async throws -> [UserSummary] {
        try await backend.followers(of: userId)
    }

    func following(of userId: UUID) async throws -> [UserSummary] {
        try await backend.following(of: userId)
    }

    func cities(of userId: UUID) async throws -> [RatedCity] {
        try await backend.fetchRatedCities(userId: userId)
    }

    func travelProfile(of userId: UUID) async throws -> TravelProfile? {
        try await backend.fetchTravelProfile(userId: userId)
    }
}
