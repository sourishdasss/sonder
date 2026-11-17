import CoreLocation
import MapKit
import SwiftUI

/// A rated city placed on the map.
struct CityMapPin: Identifiable {
    let city: RatedCity
    let coordinate: CLLocationCoordinate2D
    var id: UUID { city.id }
}

private extension MapCameraPosition {
    /// High-altitude 3D globe, turned to face `longitude`; the user can pinch and spin from here.
    static func sonderGlobe(longitude: Double = 12, distance: Double = 42_000_000) -> MapCameraPosition {
        .camera(MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 20, longitude: longitude),
            distance: distance,
            heading: 0,
            pitch: 0
        ))
    }
}

/// Starfield drawn behind the globe.
private struct StarfieldBackground: View {
    /// Deterministic star positions so the field doesn't flicker on redraw.
    private static let stars: [(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: Double)] = {
        var stars: [(x: CGFloat, y: CGFloat, radius: CGFloat, opacity: Double)] = []
        var state: UInt64 = 2_468_013_579
        func next(_ modulus: UInt64) -> UInt64 {
            state = state &* 1_103_515_245 &+ 12_345
            return (state >> 16) % modulus
        }
        for _ in 0..<240 {
            stars.append((
                x: CGFloat(next(1_000)) / 1_000,
                y: CGFloat(next(1_000)) / 1_000,
                radius: 0.35 + CGFloat(next(280)) / 280 * 1.65,
                opacity: 0.18 + Double(next(650)) / 650 * 0.82
            ))
        }
        return stars
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let rect = CGRect(
                    x: star.x * size.width,
                    y: star.y * size.height,
                    width: star.radius,
                    height: star.radius
                )
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(star.opacity)))
            }
        }
        .background(Color.black)
        .accessibilityHidden(true)
    }
}

/// World map of everywhere the user has been: rated cities plus location-tagged photos.
struct TravelMapView: View {
    @EnvironmentObject private var store: AppStore

    // Starts a little further out, then eases in once the first pins are placed.
    @State private var cameraPosition: MapCameraPosition = .sonderGlobe(distance: 62_000_000)
    @State private var hasFramedGlobe = false
    @State private var cityPins: [CityMapPin] = []
    @State private var selectedCity: CityMapPin?
    @State private var selectedPhoto: PhotoPin?
    @State private var showAddPhoto = false

    var body: some View {
        ZStack {
            StarfieldBackground()
                .ignoresSafeArea()

            Map(position: $cameraPosition) {
                ForEach(cityPins) { pin in
                    Annotation(pin.city.cityData.city, coordinate: pin.coordinate, anchor: .bottom) {
                        Button {
                            selectedCity = pin
                        } label: {
                            CityPinView(city: pin.city)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(pin.city.cityData.city), \(ScoreFormat.string(pin.city.cumulativeScore)) out of 10"
                        )
                    }
                }
                ForEach(store.photoPins) { pin in
                    Annotation(pin.locationName ?? "Photo", coordinate: pin.coordinate, anchor: .bottom) {
                        Button {
                            selectedPhoto = pin
                        } label: {
                            PhotoPinView(pin: pin)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo, \(pin.locationName ?? "unknown location")")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.imagery(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .topLeading) { statsOverlay }
        .overlay(alignment: .bottomTrailing) { controls }
        .overlay(alignment: .bottom) {
            if store.hasLoaded, cityPins.isEmpty, store.photoPins.isEmpty, store.ratedCities.isEmpty {
                emptyHint
            }
        }
        .sheet(item: $selectedCity) { pin in
            NavigationStack {
                MyCityDetailView(cityID: pin.city.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedCity = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedPhoto) { pin in
            PhotoPinDetailSheet(pin: pin)
        }
        .sheet(isPresented: $showAddPhoto) {
            AddPhotoSheet { pin in
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: pin.coordinate,
                        latitudinalMeters: 60_000,
                        longitudinalMeters: 60_000
                    ))
                }
            }
        }
        .task(id: store.ratedCities.map { "\($0.id.uuidString)|\($0.cumulativeScore)" }) {
            // Re-run when cities are added, removed or re-scored so pins never go stale.
            await resolveCityPins()
        }
    }

    // MARK: - Overlays

    private var countryCount: Int {
        var countries = Set(store.ratedCities.map { $0.cityData.country.lowercased() }.filter { !$0.isEmpty })
        for pin in store.photoPins {
            if let country = pin.countryName?.lowercased() { countries.insert(country) }
        }
        return countries.count
    }

    private var statsOverlay: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(store.ratedCities.count == 1 ? "1 city" : "\(store.ratedCities.count) cities")
                .font(.georgiaBold(16))
                .foregroundStyle(.white)
            Text(statsDetail)
                .font(.georgia(13))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 2)
        .padding(.top, 8)
        .padding(.leading, 16)
        .accessibilityElement(children: .combine)
    }

    private var statsDetail: String {
        var parts = [countryCount == 1 ? "1 country" : "\(countryCount) countries"]
        if !store.photoPins.isEmpty {
            parts.append(store.photoPins.count == 1 ? "1 photo" : "\(store.photoPins.count) photos")
        }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.8)) {
                    cameraPosition = .sonderGlobe(longitude: homeLongitude)
                }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Zoom out to the globe")

            Menu {
                Button {
                    store.isAddingCity = true
                } label: {
                    Label("Rate a city", systemImage: "building.2")
                }
                Button {
                    showAddPhoto = true
                } label: {
                    Label("Add a travel photo", systemImage: "photo.badge.plus")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.sonderOnAccent)
                    .frame(width: 56, height: 56)
                    .background(Color.sonderAccent)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            .accessibilityLabel("Add to your map")
        }
        .padding(.trailing, 18)
        .padding(.bottom, 22)
    }

    private var emptyHint: some View {
        VStack(spacing: 6) {
            Text("Your map is waiting")
                .font(.georgiaBold(16))
                .foregroundStyle(.white)
            Text("Rate a city or add a travel photo to drop your first pin.")
                .font(.georgia(13))
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: 280)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 96)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pins

    /// The globe faces the user's top-ranked city (or their latest photo) by default.
    private var homeLongitude: Double {
        cityPins.first?.coordinate.longitude ?? store.photoPins.first?.longitude ?? 12
    }

    /// Eases the camera in toward the user's places the first time pins are available.
    /// Moving the camera also prompts MapKit to lay out annotations added during the first render.
    private func frameGlobeIfNeeded() async {
        guard !hasFramedGlobe else { return }
        hasFramedGlobe = true
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 1.4)) {
            cameraPosition = .sonderGlobe(longitude: homeLongitude)
        }
    }

    /// Places each rated city on the map, geocoding (once) any city without stored coordinates.
    private func resolveCityPins() async {
        let geocoder = CityGeocoder.shared
        var pins: [CityMapPin] = []
        var pending: [RatedCity] = []

        for city in store.ratedCities {
            if let coordinate = geocoder.cachedCoordinate(for: city.cityData) {
                pins.append(CityMapPin(city: city, coordinate: coordinate))
            } else {
                pending.append(city)
            }
        }
        cityPins = pins
        if store.hasLoaded {
            await frameGlobeIfNeeded()
        }

        for city in pending {
            if Task.isCancelled { return }
            if let coordinate = await geocoder.coordinate(for: city.cityData) {
                pins.append(CityMapPin(city: city, coordinate: coordinate))
                cityPins = pins
            }
        }
    }
}

// MARK: - Pin views

struct CityPinView: View {
    let city: RatedCity

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RemoteImage(city.cityData.photoURL, placeholderIcon: "building.2")
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.sonderAccent, lineWidth: 2.5))

                Text(ScoreFormat.string(city.cumulativeScore))
                    .font(.custom("Georgia-Bold", fixedSize: 10))
                    .foregroundStyle(Color.sonderOnAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.sonderAccent)
                    .clipShape(Capsule())
                    .offset(x: 10, y: -6)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

            PinPointer()
                .fill(Color.sonderAccent)
                .frame(width: 10, height: 8)
        }
    }
}

struct PhotoPinView: View {
    let pin: PhotoPin

    var body: some View {
        VStack(spacing: 0) {
            RemoteImage(pin.photoURL, placeholderIcon: "photo")
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.white, lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            PinPointer()
                .fill(.white)
                .frame(width: 9, height: 7)
        }
    }
}

private struct PinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
