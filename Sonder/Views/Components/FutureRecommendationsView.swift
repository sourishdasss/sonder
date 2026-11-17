import SwiftUI

/// "Where to Next": a horizontal strip of destination recommendations.
struct FutureRecommendationsView: View {
    let recommendations: [DestinationRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where to Next")
                .sonderSectionTitle()
                .padding(.horizontal, SonderMetrics.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation)
                    }
                }
                .padding(.horizontal, SonderMetrics.screenPadding)
                .padding(.vertical, 6)
            }
        }
    }
}

struct RecommendationCard: View {
    let recommendation: DestinationRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.sonderSage)
                Spacer()
                if let label = recommendation.matchLabel {
                    Text(label)
                        .font(.georgiaBold(11))
                        .foregroundStyle(Color.sonderOnAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.sonderAccent)
                        .clipShape(Capsule())
                }
            }

            Text(recommendation.destination)
                .font(.georgiaBold(18))
                .foregroundStyle(Color.sonderTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.matchReason)
                .font(.georgia(13))
                .foregroundStyle(Color.sonderTextSecond)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if !recommendation.vibeTags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(Array(recommendation.vibeTags.prefix(3).enumerated()), id: \.offset) { _, tag in
                        TagChip(text: tag, size: 11)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 250, alignment: .leading)
        .frame(minHeight: 190, alignment: .top)
        .background(Color.sonderSurface)
        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        .accessibilityElement(children: .combine)
    }
}
