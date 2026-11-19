import SwiftUI

@main
struct RadaresApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { phase in
            model.scenePhaseChanged(phase)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel

    var body: some View {
        TabView(selection: $m.tab) {
            DriveView()
                .tabItem { Label("Conducir", systemImage: "car.fill") }
                .tag(AppTab.drive)
            MapScreen()
                .tabItem { Label("Mapa", systemImage: "map.fill") }
                .tag(AppTab.map)
            ListScreen()
                .tabItem { Label("Lista", systemImage: "list.bullet") }
                .tag(AppTab.list)
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(Theme.blue)
    }
}
