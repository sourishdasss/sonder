import SwiftUI

/// Photo card for a rated city: name, big score, place count and top pick.
struct CityCardView: View {
    let city: RatedCity
    /// Position in the user's rankings, shown as a badge when provided.
    var rank: Int?
    var height: CGFloat = 176

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(city.cityData.photoURL, placeholderIcon: "building.2")
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.35), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(city.cityData.city)
                        .font(.georgiaBold(21))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !city.cityData.flag.isEmpty {
                        Text(city.cityData.flag).font(.system(size: 18))
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ScoreFormat.string(city.cumulativeScore))
                        .font(.georgiaBold(32))
                        .foregroundStyle(Color.sonderScoreOnPhoto)
                        .monospacedDigit()
                    Text("/ 10")
                        .font(.georgia(15))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("·").foregroundStyle(.white.opacity(0.5))
                    Text(city.placeCount == 1 ? "1 place" : "\(city.placeCount) places")
                        .font(.georgia(13))
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let top = city.topAttractionName, !top.isEmpty {
                    Label(top, systemImage: "crown.fill")
                        .font(.georgia(12))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }
            }
            .padding(14)
        }
        .frame(height: height)
        .overlay(alignment: .topLeading) {
            if let rank {
                Text("#\(rank)")
                    .font(.georgiaBold(13))
                    .foregroundStyle(rank == 1 ? Color.sonderOnAccent : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(rank == 1 ? AnyShapeStyle(Color.sonderAccent) : AnyShapeStyle(.ultraThinMaterial))
                    .environment(\.colorScheme, .dark)
                    .clipShape(Capsule())
                    .padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let rank { parts.append("Number \(rank)") }
        parts.append(city.cityData.displayName)
        parts.append("\(ScoreFormat.string(city.cumulativeScore)) out of 10")
        parts.append(city.placeCount == 1 ? "1 place rated" : "\(city.placeCount) places rated")
        if let top = city.topAttractionName, !top.isEmpty { parts.append("Top pick: \(top)") }
        return parts.joined(separator: ", ")
    }
}

/// Compact row for a city (used in profiles and lists of other people's cities).
struct CityRowView: View {
    let city: RatedCity

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(city.cityData.photoURL, placeholderIcon: "building.2")
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("\(city.cityData.city) \(city.cityData.flag)")
                    .font(.georgiaBold(16))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .lineLimit(1)
                Text(city.topAttractionName.map { "Top pick: \($0)" } ?? city.cityData.country)
                    .font(.georgia(13))
                    .foregroundStyle(Color.sonderTextSecond)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(ScoreFormat.string(city.cumulativeScore))
                .font(.georgiaBold(22))
                .foregroundStyle(Color.sonderAccent)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sonderDivider)
        }
        .padding(10)
        .background(Color.sonderSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(city.cityData.displayName), \(ScoreFormat.string(city.cumulativeScore)) out of 10")
    }
}
