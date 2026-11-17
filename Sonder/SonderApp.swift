import SwiftUI

@main
struct SonderApp: App {
    @StateObject private var auth: AuthStore
    @StateObject private var store: AppStore
    @StateObject private var social: SocialStore

    init() {
        SonderAppearance.apply()
        let backend = BackendProvider.shared
        _auth = StateObject(wrappedValue: AuthStore(backend: backend))
        _store = StateObject(wrappedValue: AppStore(
            backend: backend,
            claude: ClaudeService(),
            // Demo mode keeps everything in memory.
            cache: Config.isDemoMode ? nil : LocalCache(),
            photoResolver: { city in
                await CityPhotoService.shared.photoURL(city: city.city, country: city.country)
            }
        ))
        _social = StateObject(wrappedValue: SocialStore(backend: backend))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(social)
                .tint(Color.sonderAccent)
        }
    }
}

/// Switches between launch, signed-out and signed-in experiences.
struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var social: SocialStore
    @ObservedObject private var toaster = Toaster.shared

    var body: some View {
        ZStack {
            Color.sonderBackground.ignoresSafeArea()

            switch auth.phase {
            case .loading:
                SplashView()
                    .transition(.opacity)
            case .signedOut:
                AuthScreen()
                    .transition(.opacity)
            case .signedIn:
                ContentRootView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.phase)
        .overlay(alignment: .top) {
            ToastOverlay(toaster: toaster)
        }
        .task {
            await auth.bootstrap()
        }
        .task(id: auth.session?.id) {
            if let userId = auth.session?.id {
                async let cities: Void = store.start(userId: userId)
                async let graph: Void = social.start(userId: userId)
                _ = await (cities, graph)
            } else {
                store.reset()
                social.reset()
            }
        }
    }
}

/// Shown for a moment at launch while a saved session is restored.
struct SplashView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Sonder")
                .font(.georgiaBold(46))
                .foregroundStyle(Color.sonderAccent)
            Text("Travel that fits you.")
                .font(.georgiaItalic(16))
                .foregroundStyle(Color.sonderTextSecond)
            ProgressView()
                .tint(Color.sonderAccent)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sonderBackground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sonder is loading")
    }
}
