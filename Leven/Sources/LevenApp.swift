import SwiftUI

@main
struct LevenApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    if !CGPreflightScreenCaptureAccess() {
                        CGRequestScreenCaptureAccess()
                    }
                }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
