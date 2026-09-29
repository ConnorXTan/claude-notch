# claude-notch

Turns the MacBook notch into a status light for Claude Code.

Run the app and one dot per running Claude Code session appears beside the
notch: yellow while Claude works, red when it is waiting on you, green when it
is done. Hover to see the list; click a dot to jump to that terminal. The
notch never had a job before; now it has one.

## Running it

```
make app && open build/ClaudeNotch.app
```

Then **Install hooks** from the menu bar icon, or from the empty notch. That
adds eight hook entries (six events) to `~/.claude/settings.json` (backed up to
`settings.json.bak` first, nothing else touched), each running
`~/.claude/hooks/notch.sh`. From then on every Claude Code session writes one
small JSON file to `~/.claude-notch/sessions/` as it changes state, and the
app watches that folder. Sessions run exactly the same with the app closed;
state lives in files it only reads.

| Dot | Meaning | Written by |
| --- | --- | --- |
| grey | idle: session started, nothing asked yet | `SessionStart` |
| yellow | working | `UserPromptSubmit`, `PostToolUse` |
| red, pulsing | needs you: a permission prompt or a question | `Notification` (`permission_prompt`, `elicitation_dialog`) |
| green | done, waiting for your next message | `Stop` |
| green, breathing | done and Claude has been waiting a while | `Notification` (`idle_prompt`) |

`PostToolUse` is the transition people forget: after you approve a permission
prompt no `UserPromptSubmit` fires, so without it the dot would stay red while
Claude is working again. `SessionEnd` deletes the file; sessions that die
without it (`kill -9`, a closed terminal window) are pruned when their process
is gone.

Hover the notch and it opens into a list grouped by repository: the repo as a
header, and under it each Claude session by the name Claude Code gave it (the
title it generates from the conversation, or yours from `/rename`; until it
has one, the terminal: "VS Code · ttys004") with the subfolder or worktree it
sits in, its state and how long ago it changed. The hook reads the name from
the session's transcript, which Claude Code hands it as `transcript_path`. A
session in a linked worktree (Claude Code's `.claude/worktrees/<name>`, or one
kept elsewhere) lists under the repository it belongs to. Two projects with
the same folder name show where they live.

When a session turns red the notch widens for three seconds to say which
folder and plays a sound (Settings turns it off). The dot keeps pulsing until
you click it or the state changes.

**Terminals.** Clicking a session brings its terminal forward: the exact tab
in iTerm and Terminal (via AppleScript, which asks for Automation permission
once), the window whose terminal runs the session in VS Code and Cursor (found from the terminal shell's directory and the editor's own list of open windows, so a session that moved into a worktree still lands in its window), the app for Ghostty, kitty,
WezTerm, Warp and the rest.

The app is a menu-bar accessory for macOS 14 or newer, shown on every display
or just the built-in one. It is not sandboxed: bringing a terminal forward
reads other processes' working directories and VS Code's own window list.

## Developing

```
swift build            debug binary in .build/debug/ClaudeNotch
swift test             the suite (session store, hook installer, terminal focus)
open Package.swift     the same targets in Xcode
make app               release build wrapped as build/ClaudeNotch.app, icon included
```

Two environment variables make the app drivable from a terminal:
`CLAUDE_NOTCH_SESSIONS_DIR` points it at a folder of hand-written session
files, and with `CLAUDE_NOTCH_SNAPSHOT_DIR` set, `kill -USR1` writes a PNG of
every notch window there (`kill -USR2` toggles the notch open). Both are how
the layouts in this README were checked; the recipe is in
[docs/testing.md](docs/testing.md).

## Layout

| Module | Role |
| --- | --- |
| `ClaudeNotch/Kit/Sessions` | session files → published list; slots, pruning, alerts, repo grouping |
| `ClaudeNotch/Kit/Hooks` | `notch.sh` and the installer that merges it into `settings.json` |
| `ClaudeNotch/Kit/Terminal` | which terminal owns a session and how to bring it forward |
| `ClaudeNotch/Kit/Notch` | notch geometry and the closed wing's dot grid |
| `ClaudeNotch/App` | the notch window, shape, dots, list, settings, menu bar |
| `hooks/notch.sh` | the hook script (the installer embeds the same bytes; a test checks) |

Everything under `Kit` is tested without a window (`swift test`); `App` is
checked with the offscreen snapshots above.

## Notes and limits

- The hooks are ordinary Claude Code hooks; `notch.sh` prints nothing,
  always exits 0, and needs nothing installed (`jq` if present, `plutil`
  otherwise), so it can never block or slow a session.
- A session that has been idle since before the hooks were installed shows
  up at its next hook event.
- Selecting the exact tab inside VS Code or Cursor is not possible from
  outside the editor; the right window comes forward instead.
- Not covered: cloud sessions and remote machines (no local hooks).

## History

This repo started as **lightswitch**, which used the MacBook's ambient light
sensor (it sits in the notch) as a gesture input, and for a while covering the
notch jumped to the session that needed you. On 2026-09-29 the sensor moved to
its own project, **notchpet**, and this repo kept the status light. The
sensor engine's history lives on in both.

## License

MIT — see [LICENSE](LICENSE).
