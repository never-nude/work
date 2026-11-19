import SwiftUI

@main
struct GoLiveApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = LiveController.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var auth = GoogleAuth.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .tint(Theme.red)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: controller.appBecameActive()
                    case .background: controller.appDidBackground()
                    default: break
                    }
                }
        }
    }
}

enum Theme {
    static let red = Color(red: 0.957, green: 0.129, blue: 0.118)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let ink = Color(red: 0.045, green: 0.045, blue: 0.05)
}

struct RootView: View {
    @EnvironmentObject private var auth: GoogleAuth

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            if auth.isSignedIn {
                LiveView()
            } else {
                SetupView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isSignedIn)
    }
}
