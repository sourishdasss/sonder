import CoreLocation
import PhotosUI
import SwiftUI

/// Pick a travel photo, read where it was taken, and pin it to the map.
///
/// The location comes from the photo's own metadata and is read on-device. If the photo has no
/// location, the user picks one of their rated cities instead.
struct AddPhotoSheet: View {
    /// Called with the new pin once it has been saved.
    var onAdded: (PhotoPin) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var selection: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var locationName: String?
    @State private var takenAt: Date?
    @State private var caption = ""
    @State private var fallbackCityID: UUID?
    @State private var isLoadingPhoto = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var citiesWithCoordinates: [RatedCity] {
        store.ratedCities.filter { CityGeocoder.shared.cachedCoordinate(for: $0.cityData) != nil }
    }

    private var resolvedCoordinate: CLLocationCoordinate2D? {
        if let coordinate { return coordinate }
        guard let fallbackCityID, let city = store.city(id: fallbackCityID) else { return nil }
        return CityGeocoder.shared.cachedCoordinate(for: city.cityData)
    }

    private var resolvedLocationName: String? {
        if coordinate != nil { return locationName }
        guard let fallbackCityID, let city = store.city(id: fallbackCityID) else { return nil }
        return city.cityData.displayName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoArea

                    if imageData != nil {
                        locationArea

                        TextField("Add a caption (optional)", text: $caption, axis: .vertical)
                            .lineLimit(1...4)
                            .sonderField()
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.georgia(14))
                            .foregroundStyle(Color.sonderDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("Location is read from the photo on your device. Only the pin’s position, place name and the resized photo are uploaded.")
                        .font(.georgia(12))
                        .foregroundStyle(Color.sonderTextSecond)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .sonderScreenBackground()
            .navigationTitle("Add a Travel Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Pin it") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(imageData == nil || resolvedCoordinate == nil)
                    }
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(isSaving)
    }

    @ViewBuilder
    private var photoArea: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            ZStack {
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                        .overlay(alignment: .bottomTrailing) {
                            Label("Change", systemImage: "photo.on.rectangle")
                                .font(.georgia(13))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .environment(\.colorScheme, .dark)
                                .clipShape(Capsule())
                                .padding(12)
                        }
                } else {
                    VStack(spacing: 10) {
                        if isLoadingPhoto {
                            ProgressView()
                        } else {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Color.sonderAccent)
                            Text("Choose a photo")
                                .font(.georgiaBold(16))
                                .foregroundStyle(Color.sonderAccent)
                            Text("Photos taken with location turned on are pinned automatically.")
                                .font(.georgia(13))
                                .foregroundStyle(Color.sonderTextSecond)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(Color.sonderSurface)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous)
                    .stroke(Color.sonderDivider, lineWidth: previewImage == nil ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    @ViewBuilder
    private var locationArea: some View {
        if coordinate != nil {
            VStack(alignment: .leading, spacing: 4) {
                Label(locationName ?? "Location found", systemImage: "mappin.circle.fill")
                    .font(.georgiaBold(16))
                    .foregroundStyle(Color.sonderTextPrimary)
                if let takenAt {
                    Text("Taken \(takenAt.formatted(date: .long, time: .omitted))")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                }
            }
            .sonderCard(padding: 14, radius: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label("This photo has no location data", systemImage: "location.slash")
                    .font(.georgiaBold(15))
                    .foregroundStyle(Color.sonderTextPrimary)
                if citiesWithCoordinates.isEmpty {
                    Text("Rate a city first, then you can pin photos to it.")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                } else {
                    Text("Pin it to one of your cities instead:")
                        .font(.georgia(13))
                        .foregroundStyle(Color.sonderTextSecond)
                    Picker("City", selection: $fallbackCityID) {
                        Text("Choose a city").tag(UUID?.none)
                        ForEach(citiesWithCoordinates) { city in
                            Text(city.cityData.displayName).tag(UUID?.some(city.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.sonderAccent)
                }
            }
            .sonderCard(padding: 14, radius: 14)
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        errorMessage = nil
        defer { isLoadingPhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "That photo couldn’t be loaded. Please try another."
            return
        }
        let info = PhotoMetadata.read(from: data)
        imageData = data
        previewImage = image
        coordinate = info.coordinate
        takenAt = info.takenAt
        locationName = nil
        fallbackCityID = nil

        if let found = info.coordinate {
            locationName = await CityGeocoder.shared.placeName(for: found)
        }
    }

    private func save() async {
        guard let imageData, let target = resolvedCoordinate else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        guard let jpeg = PhotoMetadata.preparedJPEG(from: imageData) else {
            errorMessage = "That photo couldn’t be prepared for upload."
            return
        }
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = PhotoPinDraft(
            imageData: jpeg,
            latitude: target.latitude,
            longitude: target.longitude,
            locationName: resolvedLocationName,
            caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
            takenAt: takenAt
        )
        do {
            let pin = try await store.addPhotoPin(draft)
            onAdded(pin)
            dismiss()
        } catch {
            errorMessage = ErrorCopy.message(for: error)
        }
    }
}

/// Full view of a pinned photo.
struct PhotoPinDetailSheet: View {
    let pin: PhotoPin
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteImage(pin.photoURL, contentMode: .fit, placeholderIcon: "photo")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: SonderMetrics.cornerRadius, style: .continuous))
                        .accessibilityLabel(pin.caption ?? "Travel photo")

                    VStack(alignment: .leading, spacing: 8) {
                        if let name = pin.locationName, !name.isEmpty {
                            Label(name, systemImage: "mappin.circle.fill")
                                .font(.georgiaBold(18))
                                .foregroundStyle(Color.sonderTextPrimary)
                        }
                        if let takenAt = pin.takenAt {
                            Text(takenAt.formatted(date: .long, time: .omitted))
                                .font(.georgia(14))
                                .foregroundStyle(Color.sonderTextSecond)
                        }
                        if let caption = pin.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.georgia(16))
                                .foregroundStyle(Color.sonderTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(20)
            }
            .sonderScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Delete photo")
                }
            }
            .confirmationDialog("Remove this photo from your map?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) {
                    Task {
                        await store.deletePhotoPin(pin)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
