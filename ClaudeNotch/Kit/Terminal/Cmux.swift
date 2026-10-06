import AppKit
import Foundation

/// cmux, the Ghostty-based terminal that keeps terminals in workspaces (the
/// tabs in its sidebar).
///
/// Every shell cmux starts carries `CMUX_WORKSPACE_ID` and `CMUX_SURFACE_ID`,
/// which the hook records. cmux's AppleScript dictionary speaks the same ids
/// (`tab` is a workspace, `terminal` a surface), so the app can name a
/// session's workspace and bring its exact terminal forward. cmux's own
/// socket only answers processes cmux started unless the user opens it up,
/// so AppleScript is the way in from outside.
public enum Cmux {
    public static let bundleIdentifier = "com.cmuxterm.app"

    /// What cmux has open right now.
    public struct Layout: Equatable {
        /// Workspace id → its name in the sidebar.
        public var workspaceNames: [String: String]
        /// Surface id → the workspace it is in now (a terminal can be moved
        /// to another workspace after its shell read the environment).
        public var workspaceOfSurface: [String: String]

        public init(workspaceNames: [String: String] = [:], workspaceOfSurface: [String: String] = [:]) {
            self.workspaceNames = workspaceNames
            self.workspaceOfSurface = workspaceOfSurface
        }

        public static let empty = Layout()

        /// The workspace a session is in: where its surface is now, else
        /// where its environment said it was.
        public func workspace(of session: Session) -> String {
            if !session.cmuxSurface.isEmpty, let live = workspaceOfSurface[session.cmuxSurface] {
                return live
            }
            return session.cmuxWorkspace
        }

        /// Reads `layoutScript`'s output: a `W<tab>id<tab>name` line per
        /// workspace, a `T<tab>id<tab>workspace` line per terminal.
        public static func parse(_ text: String) -> Layout {
            var layout = Layout()
            for line in text.split(whereSeparator: \.isNewline) {
                let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3, !fields[1].isEmpty else { continue }
                let id = String(fields[1])
                switch fields[0] {
                case "W": layout.workspaceNames[id] = String(fields[2])
                case "T" where !fields[2].isEmpty: layout.workspaceOfSurface[id] = String(fields[2])
                default: continue
                }
            }
            return layout
        }
    }

    // MARK: Scripts

    /// Lists every workspace and terminal. `tab` is a class in cmux's
    /// dictionary, so the separator is spelled `character id 9`. Does not
    /// launch cmux.
    static let layoutScript = """
    if application id "\(bundleIdentifier)" is not running then return ""
    set sep to character id 9
    set out to ""
    tell application id "\(bundleIdentifier)"
        with timeout of 3 seconds
            repeat with w in windows
                repeat with t in tabs of w
                    set wid to id of t
                    set out to out & "W" & sep & wid & sep & (name of t) & linefeed
                    repeat with x in terminals of t
                        set out to out & "T" & sep & (id of x) & sep & wid & linefeed
                    end repeat
                end repeat
            end repeat
        end timeout
    end tell
    return out
    """

    /// Selects the workspace holding `surface`, focuses that terminal and
    /// brings its window forward; failing that (the terminal closed),
    /// selects `workspace`. Returns whether either was found.
    public static func focusScript(surface: String, workspace: String) -> String {
        let surface = TerminalFocuser.appleScriptLiteral(surface)
        let workspace = TerminalFocuser.appleScriptLiteral(workspace)
        return """
        tell application id "\(bundleIdentifier)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with x in terminals of t
                        if id of x is \(surface) then
                            select tab t
                            focus x
                            activate window w
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            repeat with w in windows
                repeat with t in tabs of w
                    if id of t is \(workspace) then
                        select tab t
                        activate window w
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    // MARK: Reading

    public static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    /// cmux's workspaces and terminals, read through `osascript` off the
    /// main thread. Nil when cmux is not running or will not answer (the
    /// user has not allowed Automation for it).
    public static func readLayout() async -> Layout? {
        guard isRunning else { return nil }
        return await Task.detached(priority: .utility) { () -> Layout? in
            guard let output = runOsascript(layoutScript) else { return nil }
            return Layout.parse(output)
        }.value
    }

    private static func runOsascript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
