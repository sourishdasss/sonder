import SwiftUI

/// Rates one place in two quick steps:
/// 1. How was it? (loved it / it was fine / not for me), with the category editable.
/// 2. A few "which did you prefer?" comparisons against similar places, to find its rank.
struct PlaceRatingSheet: View {
    let attraction: Attraction
    let cityName: String
    /// Current rankings, used to pick comparison opponents.
    let draft: CityRatingDraft
    /// Called with the place (in its final category), how it felt, and its position in that category.
    var onComplete: (Attraction, VisitSentiment, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: AttractionCategory
    @State private var sentiment: VisitSentiment?
    @State private var search: InsertionSearch?
    @State private var questionsAsked = 0

    init(
        attraction: Attraction,
        cityName: String,
        draft: CityRatingDraft,
        onComplete: @escaping (Attraction, VisitSentiment, Int) -> Void
    ) {
        self.attraction = attraction
        self.cityName = cityName
        self.draft = draft
        self.onComplete = onComplete
        _category = State(initialValue: attraction.category == .general ? .experience : attraction.category)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let sentiment, let search, !search.isResolved {
                        comparisonStep(sentiment: sentiment, search: search)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        sentimentStep
                            .transition(.opacity)
                    }
                }
                .padding(20)
            }
            .sonderScreenBackground()
            .navigationTitle(search == nil ? "Rate this place" : "Rank it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if search != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Skip") { skipComparisons() }
                            .accessibilityHint("Places it at the bottom of its group")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: questionsAsked)
    }

    // MARK: - Step 1: sentiment

    private var sentimentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(attraction.name)
                    .font(.georgiaBold(24))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(cityName)
                    .font(.georgia(15))
                    .foregroundStyle(Color.sonderTextSecond)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Category")
                    .font(.georgiaBold(14))
                    .foregroundStyle(Color.sonderTextSecond)
                FlowLayout(spacing: 8) {
                    ForEach(AttractionCategory.placeCategories) { option in
                        Button {
                            category = option
                        } label: {
                            Label(option.shortName, systemImage: option.icon)
                                .font(.georgia(13))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(category == option ? Color.sonderOnAccent : Color.sonderTextPrimary)
                                .background(category == option ? Color.sonderAccent : Color.sonderSurface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.sonderDivider, lineWidth: category == option ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How was it?")
                    .font(.georgiaBold(20))
                    .foregroundStyle(Color.sonderTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(VisitSentiment.allCases) { option in
                    Button {
                        choose(option)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(SentimentChip.color(for: option))
                                .frame(width: 44, height: 44)
                                .background(SentimentChip.color(for: option).opacity(0.13))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(option.shortLabel)
                                    .font(.georgiaBold(17))
                                    .foregroundStyle(Color.sonderTextPrimary)
                                Text(option.detailLine)
                                    .font(.georgia(13))
                                    .foregroundStyle(Color.sonderTextSecond)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.sonderDivider)
                        }
                        .sonderCard(padding: 14, radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func choose(_ option: VisitSentiment) {
        let range = draft.insertionRange(for: option, in: category)
        let newSearch = InsertionSearch(range: range)
        if newSearch.isResolved {
            finish(sentiment: option, index: newSearch.insertionIndex)
        } else {
            questionsAsked += 1
            withAnimation(.easeInOut(duration: 0.25)) {
                sentiment = option
                search = newSearch
            }
        }
    }

    // MARK: - Step 2: comparisons

    private func comparisonStep(sentiment: VisitSentiment, search: InsertionSearch) -> some View {
        let opponent = draft.places(in: category)[search.opponentIndex]
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Which did you prefer?")
                    .font(.georgiaBold(24))
                    .foregroundStyle(Color.sonderTextPrimary)
                HStack(spacing: 8) {
                    Label(category.rawValue, systemImage: category.icon)
                        .font(.georgia(14))
                        .foregroundStyle(Color.sonderTextSecond)
                    Spacer()
                    Text(search.remainingComparisons <= 1 ? "Last one" : "Up to \(search.remainingComparisons) more")
                        .font(.georgia(12))
                        .foregroundStyle(Color.sonderTextSecond)
                }
            }

            comparisonCard(name: attraction.name, badge: "New") {
                answer(preferNew: true, sentiment: sentiment)
            }

            HStack {
                Rectangle().fill(Color.sonderDivider).frame(height: 1)
                Text("or")
                    .font(.georgiaItalic(13))
                    .foregroundStyle(Color.sonderTextSecond)
                Rectangle().fill(Color.sonderDivider).frame(height: 1)
            }
            .accessibilityHidden(true)

            comparisonCard(name: opponent.attraction.name, badge: nil) {
                answer(preferNew: false, sentiment: sentiment)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.sentiment = nil
                    self.search = nil
                }
            } label: {
                Label("Change my rating", systemImage: "arrow.uturn.backward")
                    .font(.georgia(14))
                    .foregroundStyle(Color.sonderAccent)
            }
            .padding(.top, 4)
        }
        .id(search.opponentIndex)
    }

    private func comparisonCard(name: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(Color.sonderAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.sonderAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.georgiaBold(18))
                        .foregroundStyle(Color.sonderTextPrimary)
                        .multilineTextAlignment(.leading)
                    if let badge {
                        Text(badge)
                            .font(.georgia(12))
                            .foregroundStyle(Color.sonderAccent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(Color.sonderSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.sonderAccent.opacity(badge == nil ? 0.2 : 0.5), lineWidth: badge == nil ? 1 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge == nil ? name : "\(name), new")
        .accessibilityHint("Double tap if you preferred this one")
    }

    private func answer(preferNew: Bool, sentiment: VisitSentiment) {
        guard var next = search else { return }
        if preferNew {
            next.preferNew()
        } else {
            next.preferExisting()
        }
        questionsAsked += 1
        if next.isResolved {
            finish(sentiment: sentiment, index: next.insertionIndex)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { search = next }
        }
    }

    private func skipComparisons() {
        guard let sentiment else { return }
        finish(sentiment: sentiment, index: draft.insertionRange(for: sentiment, in: category).upperBound)
    }

    private func finish(sentiment: VisitSentiment, index: Int) {
        let placed = Attraction(id: attraction.id, name: attraction.name, category: category)
        onComplete(placed, sentiment, index)
        dismiss()
    }
}
