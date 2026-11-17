import Foundation
import Testing
@testable import Sonder

@Suite("Rating draft and head-to-head ranking")
struct RatingDraftTests {
    private func food(_ name: String) -> Attraction {
        Attraction(name: name, category: .food)
    }

    @Test("Places stay grouped by tier no matter where they are inserted")
    func insertKeepsTierOrder() {
        var draft = CityRatingDraft()
        draft.insert(food("Fine A"), sentiment: .decent)
        draft.insert(food("Bad A"), sentiment: .waste)
        draft.insert(food("Loved A"), sentiment: .wouldReturn)
        // Ask for an out-of-range position: it must be clamped into the "loved" tier.
        draft.insert(food("Loved B"), sentiment: .wouldReturn, at: 99)
        draft.insert(food("Fine B"), sentiment: .decent, at: 0)

        let tiers = draft.places(in: .food).map(\.sentiment.sortTier)
        #expect(tiers == tiers.sorted())
        #expect(draft.places(in: .food).map(\.attraction.name) == ["Loved A", "Loved B", "Fine B", "Fine A", "Bad A"])
    }

    @Test("Insertion range covers exactly the matching tier")
    func insertionRange() {
        var draft = CityRatingDraft()
        draft.insert(food("L1"), sentiment: .wouldReturn)
        draft.insert(food("L2"), sentiment: .wouldReturn)
        draft.insert(food("W1"), sentiment: .waste)

        #expect(draft.insertionRange(for: .wouldReturn, in: .food) == 0..<2)
        // No "fine" places yet: the only valid spot is between the loved and disliked tiers.
        #expect(draft.insertionRange(for: .decent, in: .food) == 2..<2)
        #expect(draft.insertionRange(for: .waste, in: .food) == 2..<3)
        #expect(draft.insertionRange(for: .wouldReturn, in: .culture) == 0..<0)
    }

    @Test("Entries carry 1-based ranks and include General Appeal")
    func entriesAndRanks() {
        var draft = CityRatingDraft()
        draft.insert(food("A"), sentiment: .wouldReturn)
        draft.insert(food("B"), sentiment: .decent)
        draft.insert(Attraction(name: "Museum", category: .culture), sentiment: .wouldReturn)
        draft.generalAppeal = .decent

        let entries = draft.entries
        #expect(entries.count == 4)
        let foodEntries = entries.filter { $0.attraction.category == .food }
        #expect(foodEntries.map(\.rankInCategory) == [1, 2])
        #expect(foodEntries.allSatisfy { $0.categoryCount == 2 })
        #expect(entries.contains { $0.attraction.category == .general && $0.sentiment == .decent })
        #expect(draft.placeCount == 3)
        #expect(draft.allAttractions.count == 4)
    }

    @Test("Duplicate detection ignores case and whitespace")
    func duplicateDetection() {
        var draft = CityRatingDraft()
        draft.insert(food("Time Out Market"), sentiment: .wouldReturn)
        #expect(draft.contains(name: "  time out market "))
        #expect(!draft.contains(name: "Time Out"))
    }

    @Test("Removing the last place in a category clears the category")
    func removeClearsCategory() {
        var draft = CityRatingDraft()
        let place = food("Only")
        draft.insert(place, sentiment: .decent)
        draft.remove(id: place.id)
        #expect(!draft.hasPlaces)
        #expect(draft.activeCategories.isEmpty)
    }

    @Test("A saved city round-trips back into an identical ranking")
    func roundTripThroughRatedCity() {
        var draft = CityRatingDraft()
        draft.insert(food("A"), sentiment: .wouldReturn)
        draft.insert(food("B"), sentiment: .wouldReturn)
        draft.insert(food("C"), sentiment: .waste)
        draft.insert(Attraction(name: "Walk", category: .neighbourhood), sentiment: .decent)
        draft.generalAppeal = .wouldReturn

        let city = RatedCity.build(city: CityData(city: "Porto", country: "Portugal"), draft: draft, priorCities: [])
        let restored = CityRatingDraft(ratedCity: city)

        #expect(restored.places(in: .food).map(\.attraction.name) == ["A", "B", "C"])
        #expect(restored.places(in: .food).map(\.sentiment) == [.wouldReturn, .wouldReturn, .waste])
        #expect(restored.places(in: .neighbourhood).map(\.attraction.name) == ["Walk"])
        #expect(restored.generalAppeal == .wouldReturn)
        // Re-scoring the restored draft gives the same score.
        let rescored = ScoringEngine.cityScore(for: restored.entries)
        #expect(abs(rescored.cumulativeScore - city.cumulativeScore) < 0.0001)
        #expect(city.placeCount == 4)
    }

    // MARK: - Binary insertion

    /// Simulates answering comparisons truthfully for a place whose correct position is `target`.
    private func resolve(range: Range<Int>, target: Int) -> (index: Int, questions: Int) {
        var search = InsertionSearch(range: range)
        var questions = 0
        while !search.isResolved {
            questions += 1
            if target <= search.opponentIndex {
                search.preferNew()
            } else {
                search.preferExisting()
            }
        }
        return (search.insertionIndex, questions)
    }

    @Test("Binary search finds every possible position")
    func insertionSearchFindsEveryPosition() {
        for count in 0...12 {
            for target in 0...count {
                let result = resolve(range: 0..<count, target: target)
                #expect(result.index == target)
            }
        }
    }

    @Test("Binary search respects tier offsets")
    func insertionSearchWithOffset() {
        // Tier occupies indices 3..<7, so valid insertion positions are 3...7.
        for target in 3...7 {
            #expect(resolve(range: 3..<7, target: target).index == target)
        }
    }

    @Test("It never asks more than log2(n + 1) questions, rounded up")
    func insertionSearchQuestionBound() {
        for count in 1...32 {
            let limit = Int(ceil(log2(Double(count + 1))))
            #expect(InsertionSearch(range: 0..<count).remainingComparisons == limit)
            for target in 0...count {
                #expect(resolve(range: 0..<count, target: target).questions <= limit)
            }
        }
    }

    @Test("An empty tier needs no questions")
    func emptyRangeResolvesImmediately() {
        let search = InsertionSearch(range: 4..<4)
        #expect(search.isResolved)
        #expect(search.insertionIndex == 4)
        #expect(search.remainingComparisons == 0)
    }
}
