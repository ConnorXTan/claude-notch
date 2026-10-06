import Foundation
import ClaudeNotchKit

/// The app's view of the hook installer: current status, the last error,
/// and the two actions. Everything that reads or writes `~/.claude` goes
/// through here so Settings, the menu and the empty state agree.
@MainActor
final class HooksModel: ObservableObject {
    static let shared = HooksModel()

    let installer = HookInstaller()
    @Published private(set) var status: HookInstaller.Status = .notInstalled
    @Published private(set) var lastError: String?

    private init() {}

    var isInstalled: Bool { status == .installed }

    func refresh() {
        status = installer.status()
    }

    /// Brings an installed hook script up to this build's, so new fields
    /// reach the session files without a reinstall.
    func updateScript() {
        do {
            if try installer.updateScript() {
                Log.note(Log.sessions, "updated \(installer.scriptURL.path)")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func install() {
        do {
            try installer.install()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    func uninstall() {
        do {
            try installer.uninstall()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// One line for Settings and the menu.
    var summary: String {
        switch status {
        case .installed:
            return "Installed"
        case .notInstalled:
            return "Not installed"
        case .partial(let missing):
            return "Partly installed: missing \(missing.joined(separator: ", "))"
        case .invalidSettings(let reason):
            return "settings.json can't be read: \(reason)"
        }
    }

    var canInstall: Bool {
        if case .invalidSettings = status { return false }
        return status != .installed
    }
}
