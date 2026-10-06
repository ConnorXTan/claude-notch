import Foundation

/// Sessions that work in the same project: what the open notch lists as
/// one header with each Claude terminal under it.
///
/// In cmux a project is a workspace, the tab in its sidebar, named as cmux
/// names it; teammates Claude starts from a session there land in its
/// workspace too. Elsewhere it is a repository: a session in a subfolder or
/// a linked worktree belongs to the repository above it.
public struct ProjectGroup: Identifiable, Equatable {
    /// The repository root, or the working directory when there is none;
    /// `cmux:` and the workspace id for a cmux workspace.
    public let id: String
    /// What the header shows: the root's folder name, or the workspace's.
    public let name: String
    /// Where the root lives, home abbreviated to `~`, to tell two projects
    /// with the same name apart.
    public let location: String
    /// The directory a session's subpath is measured from.
    public let root: String
    public let sessions: [Session]

    public init(root: String, sessions: [Session]) {
        id = root
        let folder = (root as NSString).lastPathComponent
        name = folder.isEmpty ? "untitled" : folder
        let parent = (root as NSString).deletingLastPathComponent
        location = root.isEmpty ? "" : (parent as NSString).abbreviatingWithTildeInPath
        self.root = root
        self.sessions = sessions
    }

    /// A cmux workspace. Without its name from cmux (not asked yet, or not
    /// allowed) it borrows its first session's, which is what cmux names a
    /// workspace after anyway, else the folder's.
    public init(cmuxWorkspace workspace: String, name: String?, root: String, sessions: [Session]) {
        id = "cmux:" + workspace
        let borrowed = sessions.first { !$0.title.isEmpty }?.title
        let folder = (root as NSString).lastPathComponent
        self.name = [name, borrowed, folder].compactMap { $0 }.first { !$0.isEmpty } ?? "cmux"
        location = root.isEmpty ? "" : (root as NSString).abbreviatingWithTildeInPath
        self.root = root
        self.sessions = sessions
    }

    /// The state that matters most among the group's sessions.
    public var attention: SessionState {
        let order: [SessionState] = [.needsYou, .working, .done, .idle]
        return order.first { state in sessions.contains { $0.state == state } } ?? .idle
    }

    /// The session clicking the header goes to: the first one in the state
    /// that matters most.
    public var lead: Session? {
        sessions.first { $0.state == attention } ?? sessions.first
    }

    /// What sets a session apart inside its project: the path below the
    /// root, just the name for a Claude Code worktree, the folder name for a
    /// worktree kept elsewhere. Empty for a session at the root.
    public func subpath(of session: Session) -> String {
        let cwd = session.cwd
        if cwd.isEmpty || cwd == root { return "" }
        guard cwd.hasPrefix(root + "/") else { return session.folderName }
        var rel = String(cwd.dropFirst(root.count + 1))
        let worktrees = ".claude/worktrees/"
        if rel.hasPrefix(worktrees) { rel = String(rel.dropFirst(worktrees.count)) }
        return rel
    }

    /// What a row calls a session: its name, unless the header already
    /// says it (cmux names a workspace after the session in it), then which
    /// terminal it is.
    public func label(of session: Session) -> String {
        session.title == name ? session.terminalLabel : session.displayName
    }

    /// Groups in order of each project's first session; sessions keep the
    /// order they were given. `root` maps a working directory to its
    /// repository (injected so tests need no file system); `cmux` is what
    /// cmux has open, for workspace names and where terminals are now.
    public static func grouping(_ sessions: [Session],
                                root: (String) -> String = ProjectRoot.resolve,
                                cmux: Cmux.Layout = .empty) -> [ProjectGroup] {
        var order: [String] = []
        var byKey: [String: [Session]] = [:]
        var workspaces: [String: String] = [:]
        for session in sessions {
            let workspace = session.inCmux ? cmux.workspace(of: session) : ""
            let key = workspace.isEmpty ? root(session.cwd) : "cmux:" + workspace
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(session)
            if !workspace.isEmpty { workspaces[key] = workspace }
        }
        return order.map { key in
            let members = byKey[key]!
            guard let workspace = workspaces[key] else {
                return ProjectGroup(root: key, sessions: members)
            }
            return ProjectGroup(cmuxWorkspace: workspace, name: cmux.workspaceNames[workspace],
                                root: root(members[0].cwd), sessions: members)
        }
    }
}

public extension Session {
    /// "VS Code · ttys004": which terminal window this session lives in.
    var terminalLabel: String {
        let app = terminalKind.displayName
        let where_ = tty.isEmpty ? shortID : tty
        return "\(app) · \(where_)"
    }

    /// What the list calls this session: its name from Claude Code when it
    /// has one, else which terminal it lives in.
    var displayName: String {
        title.isEmpty ? terminalLabel : title
    }

    /// The repository this session works in, by folder name; the working
    /// directory's own name when it is not in one.
    var projectName: String {
        let name = (ProjectRoot.resolve(cwd) as NSString).lastPathComponent
        return name.isEmpty ? folderName : name
    }
}
