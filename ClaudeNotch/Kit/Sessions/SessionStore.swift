import Foundation

/// Watches the sessions folder, turns its files into a published list, keeps
/// slot numbers stable, prunes sessions whose process is gone, and raises an
/// alert when a session starts needing the user.
///
/// Everything the views need is derived here so they stay dumb: `slotted` is
/// exactly four entries for the closed notch, `overflow` is what did not fit.
@MainActor
public final class SessionStore: ObservableObject {
    public static let slotCount = 6

    /// `~/.claude-notch/sessions`, or `CLAUDE_NOTCH_SESSIONS_DIR` when set (for
    /// demos and for driving the app with hand-written files).
    public static let defaultDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_NOTCH_SESSIONS_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-notch/sessions", isDirectory: true)
    }()

    public static let shared = SessionStore(directory: defaultDirectory)

    /// A session that just switched to `needsYou`.
    public struct Alert: Equatable {
        public let session: Session
        public let at: Date
    }

    public let directory: URL
    public var pruneInterval: TimeInterval = 10
    /// Maps a session's working directory to the repository it lists
    /// under; tests swap in the identity.
    public var projectRoot: (String) -> String = ProjectRoot.resolve
    /// Asks cmux what it has open; tests swap in a fixed answer.
    public var cmuxLayoutReader: () async -> Cmux.Layout? = Cmux.readLayout

    /// Every known session, slotted ones first in slot order, then overflow in
    /// order of first appearance.
    @Published public private(set) var sessions: [Session] = []
    /// The most recent red transition; observed by the coordinator.
    @Published public private(set) var alert: Alert?
    /// Sessions whose pulse has been acknowledged (until their state changes).
    @Published public private(set) var acknowledged: Set<String> = []
    /// Set when the folder could not be read, for Settings to show.
    @Published public private(set) var lastError: String?
    /// cmux's workspace names and where its terminals are, as last read.
    @Published public private(set) var cmuxLayout: Cmux.Layout = .empty

    private var slots: [String: Int] = [:]
    private var firstSeen: [String: Date] = [:]
    private var order = 0
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var pruneTimer: Timer?
    private var cmuxReading = false
    private var cmuxStale = false

    public init(directory: URL) {
        self.directory = directory
    }

    deinit {
        source?.cancel()
        pruneTimer?.invalidate()
    }

    // MARK: Lifecycle

    /// Creates the folder if needed, loads it, and starts watching and pruning.
    public func start() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        reload()
        watch()
        pruneTimer?.invalidate()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: pruneInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.prune() }
        }
    }

    public func stop() {
        source?.cancel()
        source = nil
        pruneTimer?.invalidate()
        pruneTimer = nil
    }

    private func watch() {
        source?.cancel()
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            lastError = "cannot watch \(directory.path)"
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: .main)
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        let fd = descriptor
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    // MARK: Reading

    /// Re-reads every `*.json` in the folder and publishes the differences.
    public func reload() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        let decoder = JSONDecoder()
        var found: [Session] = []
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(Session.self, from: data) else { continue }
            found.append(session)
        }
        apply(found)
    }

    /// Replaces the known set with `found`, keeping slots and detecting
    /// transitions. Public so tests and previews can drive the store without
    /// touching the filesystem.
    public func apply(_ found: [Session]) {
        let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let ids = Set(found.map(\.id))

        for id in slots.keys where !ids.contains(id) { slots[id] = nil }
        for id in firstSeen.keys where !ids.contains(id) { firstSeen[id] = nil }
        acknowledged = acknowledged.intersection(ids)

        // Sessions that arrive together (the first load after launch) are
        // ordered by their last update, oldest first, so the list is stable
        // and meaningful rather than following directory order.
        let newcomers = found.filter { firstSeen[$0.id] == nil }
            .sorted { ($0.updatedAt, $0.id) < ($1.updatedAt, $1.id) }
        for session in newcomers {
            order += 1
            firstSeen[session.id] = Date(timeIntervalSinceReferenceDate: Double(order))
        }

        for session in found {
            if let old = previous[session.id], old.state != session.state {
                acknowledged.remove(session.id)
            }
            let wasRed = previous[session.id]?.state == .needsYou
            if session.state == .needsYou && !wasRed {
                alert = Alert(session: session, at: Date())
            }
        }

        // Fill free slots in order of first appearance.
        let taken = Set(slots.values)
        var free = (1...Self.slotCount).filter { !taken.contains($0) }
        for session in found.sorted(by: { firstSeen[$0.id]! < firstSeen[$1.id]! })
        where slots[session.id] == nil && !free.isEmpty {
            slots[session.id] = free.removeFirst()
        }

        sessions = found.sorted { a, b in
            switch (slots[a.id], slots[b.id]) {
            case let (sa?, sb?): return sa < sb
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return firstSeen[a.id]! < firstSeen[b.id]!
            }
        }

        if sessions.contains(where: { $0.inCmux && previous[$0.id] != $0 }) {
            refreshCmux()
        }
    }

    /// Re-reads cmux's workspaces in the background when a session runs in
    /// it: on a session change (cmux renames a workspace when the session
    /// in it gets a title) and whenever the list is about to be shown. A
    /// request while a read is under way runs once it finishes.
    public func refreshCmux() {
        guard sessions.contains(where: \.inCmux) else { return }
        guard !cmuxReading else {
            cmuxStale = true
            return
        }
        cmuxReading = true
        cmuxStale = false
        Task { [weak self, reader = cmuxLayoutReader] in
            let layout = await reader()
            guard let self else { return }
            self.cmuxReading = false
            if let layout, layout != self.cmuxLayout { self.cmuxLayout = layout }
            if self.cmuxStale { self.refreshCmux() }
        }
    }

    // MARK: Derived

    /// Exactly `slotCount` entries; nil where the slot is empty.
    public var slotted: [Session?] {
        var out = [Session?](repeating: nil, count: Self.slotCount)
        for session in sessions {
            if let slot = slots[session.id] { out[slot - 1] = session }
        }
        return out
    }

    /// The open notch's view: one group per repository or cmux workspace,
    /// each holding its terminals in slot order.
    public var groups: [ProjectGroup] {
        ProjectGroup.grouping(sessions, root: projectRoot, cmux: cmuxLayout)
    }

    /// The name of the project a session lists under: what the peek
    /// announces and the dots are read out as.
    public func projectName(of session: Session) -> String {
        groups.first { group in group.sessions.contains { $0.id == session.id } }?.name
            ?? session.projectName
    }

    /// Sessions beyond the four slots, in order of first appearance.
    public var overflow: [Session] {
        sessions.filter { slots[$0.id] == nil }
    }

    public func slot(of id: String) -> Int? { slots[id] }

    /// Red sessions the user has not acknowledged, oldest change first.
    public var needingAttention: [Session] {
        sessions.filter { $0.state == .needsYou && !acknowledged.contains($0.id) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }

    public func isAcknowledged(_ id: String) -> Bool { acknowledged.contains(id) }

    /// Stops the pulse; the dot stays red until the state actually changes.
    public func acknowledge(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        acknowledged.insert(id)
    }

    public func clearAlert() { alert = nil }

    // MARK: Pruning

    /// Deletes the file of any session whose process no longer exists. Covers
    /// crashes, `kill -9` and closed terminal windows, none of which fire
    /// `SessionEnd`.
    public func prune(now: Date = Date()) {
        var changed = false
        for session in sessions where session.pid > 0 && !Self.processExists(session.pid) {
            let url = directory.appendingPathComponent("\(session.id).json")
            try? FileManager.default.removeItem(at: url)
            changed = true
        }
        if changed { reload() }
    }

    public static func processExists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }
}
