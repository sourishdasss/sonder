import SwiftUI
import UIKit

/// Loads and caches remote images. Requests for the same URL share one download, decoded images
/// are kept in memory, and raw responses are kept on disk by `URLCache`.
actor ImagePipeline {
    static let shared = ImagePipeline()

    // NSCache is thread-safe, so it can be read without hopping onto the actor.
    private nonisolated(unsafe) let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("SonderImages", isDirectory: true)
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        memory.countLimit = 150
    }

    nonisolated func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = inFlight[url] {
            return try await existing.value
        }

        let session = session
        let task = Task<UIImage, Error> {
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url)
            } else {
                let (payload, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                data = payload
            }
            guard let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            // Decode off the main thread so scrolling stays smooth.
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let image = try await task.value
        memory.setObject(image, forKey: url as NSURL)
        return image
    }
}

/// Drop-in replacement for `AsyncImage` with caching, a shimmer placeholder and a graceful
/// fallback when there is no image.
struct RemoteImage<Fallback: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var fallback: () -> Fallback

    @State private var image: UIImage?
    @State private var failed = false

    init(
        _ urlString: String?,
        contentMode: ContentMode = .fill,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        if let urlString, !urlString.isEmpty {
            self.url = URL(string: urlString)
        } else {
            self.url = nil
        }
        self.contentMode = contentMode
        self.fallback = fallback
    }

    var body: some View {
        Group {
            if contentMode == .fit, let image {
                // Fit mode keeps the photo's own aspect ratio and takes part in layout.
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                // Fill mode: take exactly the space offered and crop the photo into it. Drawing
                // the image as an overlay stops an oversized photo from widening its container.
                Color.clear
                    .overlay {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } else if url == nil || failed {
                            fallback()
                        } else {
                            Color.sonderDivider.shimmer()
                        }
                    }
                    .clipped()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ImagePipeline.shared.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        failed = false
        do {
            let loaded = try await ImagePipeline.shared.image(for: url)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

extension RemoteImage where Fallback == PhotoPlaceholder {
    /// Remote image with the standard gradient placeholder.
    init(_ urlString: String?, contentMode: ContentMode = .fill, placeholderIcon: String = "photo") {
        self.init(urlString, contentMode: contentMode) {
            PhotoPlaceholder(icon: placeholderIcon)
        }
    }
}

/// Warm gradient shown when a city has no photo.
struct PhotoPlaceholder: View {
    var icon: String = "photo"

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.sonderSage.opacity(0.75), Color.sonderAccent.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityHidden(true)
    }
}
