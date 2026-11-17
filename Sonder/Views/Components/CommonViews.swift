import SwiftUI

// MARK: - Avatar

/// Circular initials avatar.
struct AvatarView: View {
    let initials: String
    var size: CGFloat = 40
    var filled = false

    var body: some View {
        ZStack {
            Circle()
                .fill(filled ? Color.sonderAccent : Color.sonderAccent.opacity(0.15))
            Text(initials)
                .font(.custom("Georgia-Bold", fixedSize: size * 0.38))
                .foregroundStyle(filled ? Color.sonderOnAccent : Color.sonderAccent)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.sonderAccent.opacity(filled ? 0 : 0.6), lineWidth: size > 50 ? 2 : 1))
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.sonderAccent.opacity(0.7))
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(title)
                .font(.georgiaBold(18))
                .foregroundStyle(Color.sonderTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.georgia(14))
                .foregroundStyle(Color.sonderTextSecond)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.sonderSecondary)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 28)
    }
}

// MARK: - Loading

/// Placeholder card shown while content loads.
struct SkeletonCard: View {
    var height: CGFloat = 170

    var body: some View {
        RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous)
            .fill(Color.sonderDivider.opacity(0.7))
            .frame(height: height)
            .shimmer()
            .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
            .accessibilityLabel("Loading")
    }
}

// MARK: - Score

/// Horizontal bar for a 0–10 category score.
struct ScoreBar: View {
    let category: AttractionCategory
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.sonderSage)
                    .frame(width: 20)
                Text(category.displayName)
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderTextPrimary)
                Spacer(minLength: 8)
                Text(ScoreFormat.string(score))
                    .font(.georgiaBold(14))
                    .foregroundStyle(Color.sonderAccent)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.sonderDivider.opacity(0.6))
                    Capsule()
                        .fill(Color.sonderAccent)
                        .frame(width: max(6, proxy.size.width * min(1, max(0, score / 10))))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.displayName), \(ScoreFormat.string(score)) out of 10")
    }
}

/// Small coloured chip describing how a place felt.
struct SentimentChip: View {
    let sentiment: VisitSentiment
    var compact = false

    static func color(for sentiment: VisitSentiment) -> Color {
        switch sentiment {
        case .wouldReturn: return .sonderAccent
        case .decent: return .sonderSage
        case .waste: return .sonderTextSecond
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sentiment.icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            if !compact {
                Text(sentiment.shortLabel)
                    .font(.georgia(11))
            }
        }
        .foregroundStyle(Self.color(for: sentiment))
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(Self.color(for: sentiment).opacity(0.13))
        .clipShape(Capsule())
        .accessibilityLabel(sentiment.shortLabel)
    }
}

/// Sage tag used for taste traits and vibe tags.
struct TagChip: View {
    let text: String
    var size: CGFloat = 12

    var body: some View {
        Text(text)
            .font(.georgia(size))
            .foregroundStyle(Color.sonderSage)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.sonderSage.opacity(0.13))
            .clipShape(Capsule())
    }
}

// MARK: - Flow layout

/// Wraps children onto multiple lines, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(width: result.widths[index], height: nil)
            )
        }
    }

    private func arrange(width: CGFloat?, subviews: Subviews) -> (size: CGSize, origins: [CGPoint], widths: [CGFloat]) {
        let maxWidth = width ?? .infinity
        var origins: [CGPoint] = []
        var widths: [CGFloat] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // A single item wider than the row: constrain it so its text can wrap.
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            widths.append(size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            widest = max(widest, x - spacing)
        }
        let totalWidth = maxWidth.isFinite ? maxWidth : widest
        return (CGSize(width: totalWidth, height: y + rowHeight), origins, widths)
    }
}

// MARK: - People

struct FollowButton: View {
    let user: UserSummary
    @EnvironmentObject private var social: SocialStore

    var body: some View {
        if !social.isMe(user.id) {
            let following = social.isFollowing(user.id)
            Button {
                Task { await social.toggleFollow(user) }
            } label: {
                Text(following ? "Following" : "Follow")
                    .font(.georgiaBold(13))
                    .foregroundStyle(following ? Color.sonderAccent : Color.sonderOnAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(following ? Color.sonderAccent.opacity(0.12) : Color.sonderAccent)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.sonderAccent, lineWidth: following ? 1 : 0))
            }
            .buttonStyle(.plain)
            .disabled(social.pending.contains(user.id))
            .sensoryFeedback(.selection, trigger: following)
            .accessibilityLabel(following ? "Unfollow \(user.name)" : "Follow \(user.name)")
        }
    }
}

struct UserRow: View {
    let user: UserSummary
    var subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: user.initials, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.name)
                    .font(.georgiaBold(16))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            FollowButton(user: user)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Navigation

/// Destinations shared by every tab's navigation stack.
enum Route: Hashable {
    /// One of the signed-in user's cities, looked up live so edits show immediately.
    case myCity(UUID)
    /// A city rated by someone else (read-only snapshot).
    case city(CitySnapshot)
    case user(UserSummary)
    case followers(UserSummary)
    case following(UserSummary)
    case findPeople
    case settings
}

/// Hashable wrapper so a `RatedCity` can travel through a navigation path.
struct CitySnapshot: Hashable {
    let city: RatedCity
    let ownerName: String

    static func == (lhs: CitySnapshot, rhs: CitySnapshot) -> Bool { lhs.city.id == rhs.city.id }
    func hash(into hasher: inout Hasher) { hasher.combine(city.id) }
}

extension View {
    /// Registers Sonder's shared navigation destinations on a `NavigationStack`.
    func sonderDestinations(zoomNamespace: Namespace.ID? = nil) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .myCity(let id):
                MyCityDetailView(cityID: id)
                    .cityZoomDestination(id: id, in: zoomNamespace)
            case .city(let snapshot):
                CityDetailView(city: snapshot.city, ownerName: snapshot.ownerName)
            case .user(let user):
                UserProfileView(user: user)
            case .followers(let user):
                FollowListView(user: user, mode: .followers)
            case .following(let user):
                FollowListView(user: user, mode: .following)
            case .findPeople:
                FindPeopleView()
            case .settings:
                SettingsView()
            }
        }
    }

    /// Marks a card as the origin of the zoom transition into its detail screen (iOS 18+).
    @ViewBuilder
    func cityZoomSource(id: UUID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func cityZoomDestination(id: UUID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }

    /// Standard page background for scrolling screens.
    ///
    /// On iOS 26+ bars are transparent by default, which lets content run under the title.
    /// `hardTopEdge` asks for a crisp edge instead so titles stay legible while scrolling.
    @ViewBuilder
    func sonderScreenBackground(hardTopEdge: Bool = true) -> some View {
        if #available(iOS 26.0, *), hardTopEdge {
            background(Color.sonderBackground.ignoresSafeArea())
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            background(Color.sonderBackground.ignoresSafeArea())
        }
    }
}
