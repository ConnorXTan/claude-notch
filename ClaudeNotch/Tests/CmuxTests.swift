import XCTest
@testable import ClaudeNotchKit

@MainActor
final class CmuxTests: XCTestCase {
    private let leaderboard = "0D17AD56-CACC-49B0-BB94-B57BF40C26F1"
    private let portfolio = "A716FE6C-B853-4FB4-936F-8A199622F122"
    private let downloads = "/Users/connortan/Downloads"

    private func session(_ id: String, _ state: SessionState = .idle, cwd: String? = nil,
                         title: String = "", workspace: String = "", surface: String = "",
                         term: String = "ghostty", tty: String = "ttys001") -> Session {
        Session(id: id, state: state, cwd: cwd ?? downloads, tty: tty, termProgram: term,
                title: title, cmuxWorkspace: workspace, cmuxSurface: surface)
    }

    // MARK: Session

    func testDecodesTheCmuxFieldsAndToleratesTheirAbsence() throws {
        let new = #"{"session_id":"a","state":"working","cwd":"/p","term_program":"ghostty","cmux_workspace":"W1","cmux_surface":"S1"}"#
        let old = #"{"session_id":"b","state":"working","cwd":"/p","term_program":"ghostty"}"#
        let a = try JSONDecoder().decode(Session.self, from: Data(new.utf8))
        let b = try JSONDecoder().decode(Session.self, from: Data(old.utf8))
        XCTAssertEqual(a.cmuxWorkspace, "W1")
        XCTAssertEqual(a.cmuxSurface, "S1")
        XCTAssertTrue(a.inCmux)
        XCTAssertEqual(b.cmuxWorkspace, "")
        XCTAssertFalse(b.inCmux)

        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(back.cmuxSurface, "S1")
    }

    func testCmuxWinsOverWhatTheShellReported() {
        XCTAssertEqual(session("a", surface: "S1").terminalKind, .cmux)
        XCTAssertEqual(session("b", workspace: "W1", term: "tmux").terminalKind, .cmux,
                       "a teammate in Claude's tmux still lives in cmux")
        XCTAssertEqual(session("c").terminalKind, .ghostty, "plain Ghostty stays Ghostty")
        XCTAssertEqual(session("a", surface: "S1", tty: "ttys003").terminalLabel, "cmux · ttys003")
        XCTAssertEqual(TerminalKind(termProgram: "cmux"), .cmux)
    }

    // MARK: Layout

    func testLayoutParsesWorkspacesAndTerminals() {
        let text = "W\t\(leaderboard)\tLeaderboard phase two\n"
            + "T\tFD79\t\(leaderboard)\n"
            + "T\t80AD\t\(leaderboard)\n"
            + "W\t\(portfolio)\tTabs\tin a name\n"
            + "T\t5584\t\(portfolio)\n"
            + "garbage\n\nT\t\t\(portfolio)\nT\tlonely\t\n"
        let layout = Cmux.Layout.parse(text)
        XCTAssertEqual(layout.workspaceNames, [leaderboard: "Leaderboard phase two", portfolio: "Tabs\tin a name"])
        XCTAssertEqual(layout.workspaceOfSurface, ["FD79": leaderboard, "80AD": leaderboard, "5584": portfolio])
        XCTAssertEqual(Cmux.Layout.parse(""), .empty)
    }

    func testAMovedTerminalListsUnderTheWorkspaceItIsInNow() {
        let layout = Cmux.Layout(workspaceOfSurface: ["S1": portfolio])
        XCTAssertEqual(layout.workspace(of: session("a", workspace: leaderboard, surface: "S1")), portfolio)
        XCTAssertEqual(layout.workspace(of: session("b", workspace: leaderboard, surface: "S9")), leaderboard,
                       "a terminal cmux did not list keeps the workspace it started in")
    }

    func testFocusScriptQuotesTheIds() {
        let script = Cmux.focusScript(surface: #"S"1"#, workspace: "W\\1")
        XCTAssertTrue(script.contains(#"if id of x is "S\"1" then"#))
        XCTAssertTrue(script.contains(#"if id of t is "W\\1" then"#))
        XCTAssertTrue(script.contains(#"tell application id "com.cmuxterm.app""#))
    }

    // MARK: Grouping

    /// Everything here runs from ~/Downloads, which grouped by repository
    /// is one "Downloads" project. By cmux workspace it is what the sidebar
    /// shows, with the teammates under the session that started them.
    func testSessionsInCmuxGroupByWorkspace() {
        let layout = Cmux.Layout(
            workspaceNames: [leaderboard: "Leaderboard phase two", portfolio: "Portfolio bio edits"],
            workspaceOfSurface: ["FD79": leaderboard, "5584": portfolio])
        let sessions = [
            session("lead", .done, title: "Leaderboard phase two", workspace: leaderboard, surface: "FD79"),
            session("bio", .idle, title: "Portfolio bio edits", workspace: portfolio, surface: "5584", tty: "ttys000"),
            session("mate1", .working, title: "Security review", workspace: leaderboard, surface: "FD79", term: "tmux"),
            session("mate2", .needsYou, cwd: "/private/tmp/scratch/wt-db", title: "Database",
                    workspace: leaderboard, surface: "FD79", term: "tmux"),
            session("plain", .idle, cwd: "/Users/connortan/notes"),
        ]
        let groups = ProjectGroup.grouping(sessions, root: { $0 }, cmux: layout)
        XCTAssertEqual(groups.map(\.name), ["Leaderboard phase two", "Portfolio bio edits", "notes"])
        XCTAssertEqual(groups.map(\.id), ["cmux:" + leaderboard, "cmux:" + portfolio, "/Users/connortan/notes"])
        XCTAssertEqual(groups[0].sessions.map(\.id), ["lead", "mate1", "mate2"])
        XCTAssertEqual(groups[0].sessions.map(groups[0].subpath(of:)), ["", "", "wt-db"])
        XCTAssertEqual(groups[0].sessions.map(groups[0].label(of:)),
                       ["cmux · ttys001", "Security review", "Database"],
                       "the session the workspace is named after shows its terminal instead")
        XCTAssertEqual(groups[0].attention, .needsYou)
        XCTAssertEqual(groups[0].lead?.id, "mate2", "the header goes where you are needed")
        XCTAssertEqual(groups[1].lead?.id, "bio")
    }

    func testAWorkspaceIsMeasuredFromWhereMostOfItsSessionsWork() {
        let sessions = [
            session("mate", cwd: "/private/tmp/scratch/wt-db", workspace: leaderboard),
            session("lead", workspace: leaderboard),
            session("mate2", workspace: leaderboard),
        ]
        let group = ProjectGroup.grouping(sessions, root: { $0 })[0]
        XCTAssertEqual(group.root, downloads)
        XCTAssertEqual(group.sessions.map(group.subpath(of:)), ["wt-db", "", ""])
        XCTAssertEqual(ProjectGroup.commonest(["a", "b"]), "a", "a tie goes to the first")
        XCTAssertEqual(ProjectGroup.commonest([]), "")
    }

    func testWithoutCmuxsAnswerAWorkspaceBorrowsItsSessionsName() {
        let sessions = [
            session("a", title: "", workspace: leaderboard, surface: "FD79"),
            session("b", title: "Leaderboard phase two", workspace: leaderboard, surface: "FD79"),
            session("c", workspace: portfolio, surface: "5584"),
        ]
        let groups = ProjectGroup.grouping(sessions, root: { $0 })
        XCTAssertEqual(groups.map(\.name), ["Leaderboard phase two", "Downloads"])
        XCTAssertEqual(groups[1].location, "~/Downloads")
    }

    // MARK: Process environment

    func testParsesProcArgs() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(2)) { bytes += $0 }
        bytes += Array("/usr/local/bin/claude".utf8) + [0, 0, 0, 0]
        bytes += Array("claude".utf8) + [0] + Array("--resume".utf8) + [0]
        bytes += Array("CMUX_SURFACE_ID=S1".utf8) + [0] + Array("EQ=a=b".utf8) + [0] + Array("NOEQ".utf8) + [0]
        bytes += [0] + Array("APPLE_JUNK=x".utf8) + [0]
        XCTAssertEqual(ProcessEnvironment.parse(bytes), ["CMUX_SURFACE_ID": "S1", "EQ": "a=b"])
        XCTAssertNil(ProcessEnvironment.parse([1, 0]))
    }

    func testReadsThisProcesssEnvironment() throws {
        let environment = try XCTUnwrap(ProcessEnvironment.variables(of: getpid()))
        XCTAssertEqual(environment["PATH"], ProcessInfo.processInfo.environment["PATH"])
        XCTAssertNil(ProcessEnvironment.variables(of: 0))
    }

    // MARK: Store

    /// A session idle since before the hook knew about cmux has no ids in
    /// its file; its process's environment has them.
    func testTheStoreFillsInCmuxFromTheProcessForOlderFiles() {
        let store = SessionStore(directory: FileManager.default.temporaryDirectory)
        store.projectRoot = { $0 }
        store.cmuxLayoutReader = { nil }
        var reads: [pid_t] = []
        store.processEnvironment = { pid in
            reads.append(pid)
            switch pid {
            case 42: return ["CMUX_WORKSPACE_ID": self.leaderboard, "CMUX_SURFACE_ID": "FD79"]
            case 43: return ["CMUX_WORKSPACE_ID": "evil\"; do shell script", "CMUX_SURFACE_ID": ""]
            default: return nil
            }
        }
        let old = Session(id: "old", state: .idle, cwd: downloads, pid: 42, termProgram: "ghostty",
                          title: "Leaderboard phase two")
        let odd = Session(id: "odd", state: .idle, cwd: "/tmp/odd", pid: 43)
        let new = session("new", workspace: portfolio, surface: "5584")

        store.apply([old, odd, new])
        XCTAssertEqual(store.sessions.first { $0.id == "old" }?.cmuxSurface, "FD79")
        XCTAssertEqual(store.sessions.first { $0.id == "old" }?.terminalKind, .cmux)
        XCTAssertFalse(store.sessions.first { $0.id == "odd" }!.inCmux, "only UUID-like ids are taken")
        XCTAssertEqual(Set(store.groups.map(\.id)), ["cmux:" + leaderboard, "/tmp/odd", "cmux:" + portfolio])

        store.apply([old, odd, new])
        XCTAssertEqual(reads, [42, 43], "once per process; a file that has ids is not looked up")
    }

    func testTheStoreReadsCmuxWhenACmuxSessionChanges() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CmuxTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SessionStore(directory: dir)
        store.projectRoot = { $0 }
        var reads = 0
        store.cmuxLayoutReader = {
            reads += 1
            return Cmux.Layout(workspaceNames: [self.leaderboard: "Renamed in cmux"])
        }

        store.apply([session("plain", cwd: "/tmp/p")])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads, 0, "no cmux session, no Apple events")

        let lead = session("lead", title: "Leaderboard phase two", workspace: leaderboard)
        store.apply([lead])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(store.groups.map(\.name), ["Renamed in cmux"])
        XCTAssertEqual(store.projectName(of: lead), "Renamed in cmux")

        store.apply([lead])
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reads, 1, "an unchanged session does not ask again")
    }
}
