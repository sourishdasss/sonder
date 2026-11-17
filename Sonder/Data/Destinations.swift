import Foundation

/// A destination Sonder can recommend, described by how strong it is in each category (0–1).
struct Destination: Hashable, Sendable {
    let city: String
    let country: String
    let knownFor: String
    let vibeTags: [String]
    let affinity: [AttractionCategory: Double]

    private init(
        _ city: String,
        _ country: String,
        knownFor: String,
        tags: [String],
        culture: Double,
        nature: Double,
        food: Double,
        neighbourhood: Double,
        experience: Double,
        landmark: Double
    ) {
        self.city = city
        self.country = country
        self.knownFor = knownFor
        self.vibeTags = tags
        self.affinity = [
            .culture: culture,
            .nature: nature,
            .food: food,
            .neighbourhood: neighbourhood,
            .experience: experience,
            .landmark: landmark
        ]
    }

    /// Recommendation pool for the on-device taste engine.
    static let catalogue: [Destination] = [
        Destination("Tokyo", "Japan", knownFor: "depachika food halls and distinct neighbourhoods",
                    tags: ["Food", "Neighbourhoods", "Neon"],
                    culture: 0.8, nature: 0.5, food: 1.0, neighbourhood: 0.9, experience: 0.9, landmark: 0.7),
        Destination("Paris", "France", knownFor: "world-class museums and café-lined streets",
                    tags: ["Museums", "Cafés", "Architecture"],
                    culture: 1.0, nature: 0.5, food: 0.9, neighbourhood: 0.9, experience: 0.6, landmark: 0.9),
        Destination("Lisbon", "Portugal", knownFor: "hillside neighbourhoods and pastry counters",
                    tags: ["Walkable", "Viewpoints", "Pastries"],
                    culture: 0.6, nature: 0.4, food: 0.8, neighbourhood: 1.0, experience: 0.6, landmark: 0.8),
        Destination("New York", "United States", knownFor: "landmark museums and endless neighbourhoods",
                    tags: ["Museums", "Skyline", "Bagels"],
                    culture: 0.9, nature: 0.5, food: 0.9, neighbourhood: 0.9, experience: 0.9, landmark: 0.9),
        Destination("Kyoto", "Japan", knownFor: "temples, gardens and quiet lanes",
                    tags: ["Temples", "Gardens", "Tradition"],
                    culture: 1.0, nature: 0.8, food: 0.8, neighbourhood: 0.8, experience: 0.7, landmark: 0.8),
        Destination("Marrakech", "Morocco", knownFor: "medina souks and rooftop dinners",
                    tags: ["Souks", "Spice", "Riads"],
                    culture: 0.8, nature: 0.4, food: 0.8, neighbourhood: 0.9, experience: 0.8, landmark: 0.6),
        Destination("New Orleans", "United States", knownFor: "live music and Creole cooking",
                    tags: ["Jazz", "Creole Food", "Late Nights"],
                    culture: 0.7, nature: 0.4, food: 1.0, neighbourhood: 0.8, experience: 0.9, landmark: 0.5),
        Destination("Bali", "Indonesia", knownFor: "rice terraces and temple ceremonies",
                    tags: ["Rice Terraces", "Surf", "Temples"],
                    culture: 0.7, nature: 1.0, food: 0.6, neighbourhood: 0.5, experience: 0.9, landmark: 0.7),
        Destination("Mexico City", "Mexico", knownFor: "street tacos, markets and leafy colonias",
                    tags: ["Street Food", "Markets", "Murals"],
                    culture: 0.9, nature: 0.5, food: 1.0, neighbourhood: 0.9, experience: 0.7, landmark: 0.6),
        Destination("Porto", "Portugal", knownFor: "riverside lanes and port cellars",
                    tags: ["Walkable", "Wine", "Tiles"],
                    culture: 0.6, nature: 0.5, food: 0.8, neighbourhood: 1.0, experience: 0.6, landmark: 0.7),
        Destination("Copenhagen", "Denmark", knownFor: "bike-friendly streets and inventive food",
                    tags: ["Design", "Cycling", "New Nordic"],
                    culture: 0.7, nature: 0.6, food: 0.9, neighbourhood: 0.9, experience: 0.6, landmark: 0.5),
        Destination("Buenos Aires", "Argentina", knownFor: "barrio life, steakhouses and tango",
                    tags: ["Barrios", "Steak", "Tango"],
                    culture: 0.8, nature: 0.4, food: 0.9, neighbourhood: 1.0, experience: 0.8, landmark: 0.5),
        Destination("Istanbul", "Türkiye", knownFor: "bazaars, mosques and Bosphorus views",
                    tags: ["Bazaars", "History", "Ferries"],
                    culture: 1.0, nature: 0.4, food: 0.9, neighbourhood: 0.8, experience: 0.7, landmark: 0.9),
        Destination("Cape Town", "South Africa", knownFor: "mountain hikes and coastline",
                    tags: ["Hiking", "Coast", "Wine"],
                    culture: 0.6, nature: 1.0, food: 0.7, neighbourhood: 0.6, experience: 0.9, landmark: 0.9),
        Destination("Vancouver", "Canada", knownFor: "seawall walks and mountains on the doorstep",
                    tags: ["Outdoors", "Seawall", "Sushi"],
                    culture: 0.5, nature: 1.0, food: 0.7, neighbourhood: 0.7, experience: 0.8, landmark: 0.6),
        Destination("Rome", "Italy", knownFor: "ancient landmarks and trattoria dinners",
                    tags: ["History", "Pasta", "Piazzas"],
                    culture: 1.0, nature: 0.4, food: 0.9, neighbourhood: 0.8, experience: 0.6, landmark: 1.0),
        Destination("Hanoi", "Vietnam", knownFor: "old-quarter street food",
                    tags: ["Street Food", "Old Quarter", "Coffee"],
                    culture: 0.7, nature: 0.4, food: 1.0, neighbourhood: 0.8, experience: 0.7, landmark: 0.5),
        Destination("Edinburgh", "Scotland", knownFor: "a walkable old town and hilltop views",
                    tags: ["Old Town", "Views", "Pubs"],
                    culture: 0.8, nature: 0.7, food: 0.5, neighbourhood: 0.9, experience: 0.6, landmark: 0.9),
        Destination("Queenstown", "New Zealand", knownFor: "alpine scenery and adventure sports",
                    tags: ["Adventure", "Lakes", "Hiking"],
                    culture: 0.3, nature: 1.0, food: 0.5, neighbourhood: 0.4, experience: 1.0, landmark: 0.8),
        Destination("Oaxaca", "Mexico", knownFor: "mole, mezcal and craft markets",
                    tags: ["Mole", "Markets", "Craft"],
                    culture: 0.9, nature: 0.5, food: 1.0, neighbourhood: 0.8, experience: 0.7, landmark: 0.4),
        Destination("Seoul", "South Korea", knownFor: "late-night food alleys and palace districts",
                    tags: ["Night Markets", "Palaces", "Cafés"],
                    culture: 0.8, nature: 0.5, food: 1.0, neighbourhood: 0.8, experience: 0.9, landmark: 0.7),
        Destination("Vienna", "Austria", knownFor: "grand museums and coffee houses",
                    tags: ["Museums", "Coffee Houses", "Music"],
                    culture: 1.0, nature: 0.6, food: 0.7, neighbourhood: 0.8, experience: 0.6, landmark: 0.8),
        Destination("Reykjavík", "Iceland", knownFor: "geothermal pools and wild landscapes",
                    tags: ["Landscapes", "Hot Springs", "Northern Lights"],
                    culture: 0.5, nature: 1.0, food: 0.5, neighbourhood: 0.5, experience: 0.9, landmark: 0.8),
        Destination("Singapore", "Singapore", knownFor: "hawker centres and garden skylines",
                    tags: ["Hawker Food", "Gardens", "Skyline"],
                    culture: 0.6, nature: 0.7, food: 1.0, neighbourhood: 0.7, experience: 0.7, landmark: 0.8)
    ]
}
