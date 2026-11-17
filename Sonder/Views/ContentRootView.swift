import SwiftUI

/// The signed-in shell: four tabs plus the app-wide "add / edit a city" flows.
struct ContentRootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefresh = Date()

    var body: some View {
        TabView(selection: $store.selectedTab) {
            FeedView()
                .tabItem { Label("Feed", systemImage: "square.stack.fill") }
                .tag(AppStore.Tab.feed)

            TravelMapView()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppStore.Tab.map)

            ListsView()
                .tabItem { Label("Lists", systemImage: "list.star") }
                .tag(AppStore.Tab.lists)

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
                .tag(AppStore.Tab.profile)
        }
        .sheet(isPresented: $store.isAddingCity) {
            AddCityPickerView()
        }
        .fullScreenCover(item: $store.editingCity) { city in
            RateCityView(city: city.cityData, existing: city)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pick up other people's activity after the app has been in the background a while.
            guard phase == .active, Date().timeIntervalSince(lastRefresh) > 300 else { return }
            lastRefresh = Date()
            Task { await store.refreshAll() }
        }
    }
}
