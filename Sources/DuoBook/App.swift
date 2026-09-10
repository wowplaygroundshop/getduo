import SwiftUI

@main
struct DuoBookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var engine = FoldEngine.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: engine.paused || !engine.settings.enabled
                  ? "laptopcomputer.slash" : "laptopcomputer")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        FoldEngine.shared.start()

        let seen = UserDefaults.standard.bool(forKey: "seenOnboarding")
        if !seen || !CGPreflightScreenCaptureAccess() {
            UserDefaults.standard.set(true, forKey: "seenOnboarding")
            SettingsWindow.show()
        }
    }
}
