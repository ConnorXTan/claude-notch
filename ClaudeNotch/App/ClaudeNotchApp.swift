import SwiftUI
import ClaudeNotchKit

@main
struct ClaudeNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            StatusMenu()
        } label: {
            Image(nsImage: StatusIcon.image())
        }

        Settings {
            SettingsView()
        }
    }
}
