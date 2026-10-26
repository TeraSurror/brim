# Brim

A native macOS app that turns the MacBook notch into a hover-to-expand panel. Hover the notch for a peek, click or keep
hovering for the full panel, and put glanceable, controllable things right where the pointer already goes. The shell is
built to host pluggable modules; media controls are the first real one.

- **Notch window** that never takes focus, follows every Space, and works over full-screen apps
- **Peek → expand → collapse** driven by a small, unit-tested state machine
- **One panel per screen**, including a slim handle on displays without a notch
- **Module host** with clock, Now Playing and Agent Status modules; AI tools plug in without touching the window shell
- **Media controls**: artwork in the peek, then a full card with title, artist, progress, seek and transport buttons
  for anything macOS reports (Spotify, Music, Safari/YouTube, …), with optional direct Spotify/Music control
- **Agent status**: local Claude Code/Codex/Cursor/VS Code events over a Unix socket or `brim://` URL, with waiting,
  working, done and failed rows in the panel
- **Agent alerts**: opt-in notch alert or macOS banner when an agent is waiting or fails, with a click that opens the
  project in Finder
- **Works with no media**: the module disappears from the peek and shows a quiet empty state in the panel
- **Settings** for hover/collapse timing, launch at login, modules and multi-display behaviour
- **No network access, no analytics, no menu bar icon** (M1/M2; Agent Status is local-only)

## Status

M1 (notch panel shell), M2 (media controls), M3 F7 (agent status) and M3 F8 (agent alerts/open project) are implemented
and unit tested. Real-player, real-Claude-Code-hook and visual sign-off still need a person at the screen. See
[`docs/PROGRESS.md`](docs/PROGRESS.md) for what is verified and the next session's starting point; the checklists are in
[`docs/TESTING.md`](docs/TESTING.md).

## Documentation

- [Build progress and handoff notes](docs/PROGRESS.md)
- [Manual testing checklist and known limitations](docs/TESTING.md)
- [Project spec](Brim%20%E2%80%94%20macOS%20Notch%20Panel%20Spec.md)
- [Agent guide](AGENTS.md)

## Build and run

Requires macOS 14 or later and Swift 5.10+. Building the app also needs **CMake** and network access the first time,
because it builds the pinned MediaRemote helper into the bundle.

```sh
swift test          # unit tests (does not need the media helper)
./build.sh          # builds build/Brim.app (ad-hoc signed), including the media helper
open build/Brim.app
```

`./build.sh debug` builds a debug bundle instead. `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh` builds without media; the rest
of Brim works. The helper is [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) v0.7.7
(BSD-3), cloned into `.build/media-adapter-src` and never committed. Its license is copied into the app bundle. The app is an agent (`LSUIElement`): no Dock icon. Hover the notch,
or the slim handle at the top center of a display without a notch, to open the panel. Right-click the open panel for
Settings and Quit; ⌘, also opens Settings while a Brim window is focused.

Bundle ID: `com.harshshelar.brim`. Settings live in
`~/Library/Application Support/Brim/settings.json` (versioned JSON; corrupt files are moved aside, not deleted).

## Agent status (M3 F7)

Agent Status is off by default. Turn it on in **Settings → Modules → Agent Status**; no permission prompt appears. It
starts a local Unix socket at `~/Library/Application Support/Brim/agent.sock` (`0600`, removed on quit) and accepts
`brim://agent` URLs. Nothing leaves the Mac.

A tool reports one JSON object per line:

```sh
printf '%s\n' '{"agent":"claude-code","session":"demo","status":"working","title":"Fix the parser","detail":"Running tests"}' \
  | nc -U "$HOME/Library/Application Support/Brim/agent.sock"
```

or opens the equivalent URL:

```sh
open -g 'brim://agent?agent=claude-code&session=demo&status=waiting&title=Approve%20a%20tool%20call'
```

Statuses are `working`, `waiting`, `done` and `error`; `title`, `detail`, `costUSD`, `cwd` and `timestamp` are
optional. `action=dismiss&agent=…&session=…` removes one row and `action=clear` clears the roster. The panel sorts
waiting first, then failures, working and done.

Claude Code is the reference integration: [`docs/TESTING.md`](docs/TESTING.md) has a ready-to-save
`~/.brim/claude-hook.sh` and the `~/.claude/settings.json` hooks. Codex, Cursor, VS Code extensions and plain scripts
use the same contract.

Agent alerts are a separate opt-in in **Settings → General → Agents**. Brim shows a small card under the notch while
the panel is closed, and uses a macOS notification banner when the system allows it. Clicking the alert's folder button
opens the session's `cwd` in Finder; agent rows have the same button.

> System banners require a signed build. On the ad-hoc development build macOS returns “Notifications are not allowed
> for this application”, so Brim uses the notch alert instead. The behavior is otherwise identical.

## Code layout

- `Sources/BrimKit/Window/`: all AppKit panel code (`NSPanel`, frames, pointer tracking, per-screen manager, notch alerts)
- `Sources/BrimKit/State/`: pure hover/expand geometry, the state machine, agent roster and alert geometry, driven by an
  injected scheduler/clock
- `Sources/BrimKit/Modules/`: `BrimModule`, registry, the clock, Now Playing and Agent Status modules
- `Sources/BrimKit/Services/`: protocols plus real implementations (screens, login item, settings, permissions,
  MediaRemote helper process, Spotify/Music Apple Events, now-playing coordinator, agent Unix socket/URL router,
  local notifications and Finder project opening)
- `Sources/BrimKit/Model/`: `ScreenInfo`, `PanelState`, `NowPlaying`, `AgentEvent`, `AgentNotification`, `Settings`,
  permissions
- `scripts/build-media-adapter.sh`: builds the pinned third-party helper into `.build/media-adapter`
- `Sources/BrimKit/UI/`: SwiftUI panel, media/agent cards and settings views; no `NSPanel` or `NSScreen` access
- `Sources/BrimKit/App/`: composition root, app delegate, settings window, shared model
- `Tests/BrimTests/`: fakes and unit tests
- `docs/`: progress, manual testing

Architecture rules and conventions are in [`AGENTS.md`](AGENTS.md). In short: one `NSPanel` per screen, AppKit stays in
`Window/`/`App/`, `State/` is pure, every system API sits behind a protocol with a fake, and features are modules.

## Troubleshooting

### Media does not appear

- Turn the module on: **Settings → Modules → Now Playing**. It is off by default so the M1 panel stays unchanged.
- The first enable shows Brim's explanation, then macOS may ask for Automation (only for Spotify or Music that is
  running). Declining still leaves macOS-reported media working.
- Media appears only while a panel is open — Brim deliberately stops the helper when it collapses to keep idle cost
  near zero. The first peek can take a fraction of a second to show the track.
- Check the helper and the log:
  ```sh
  pgrep -fl 'mediaremote-adapter|brim-media-supervisor'
  log stream --predicate 'subsystem == "com.harshshelar.brim"'
  ```
- If the helper is missing or broken, media still works through Automation for a running Spotify/Music, and the panel
  shows the empty state otherwise. Rebuild with `./scripts/build-media-adapter.sh --force`, then run the `test` command
  printed in [`docs/TESTING.md`](docs/TESTING.md). A future macOS release can close the Perl/MediaRemote route.
- `swift run` does not have the bundle resources; point `BRIM_MEDIA_ADAPTER_PATH` at `.build/media-adapter` (or use
  `./build.sh`).

### Agent status does not appear

- Turn the module on: **Settings → Modules → Agent Status**. It is off by default.
- Check the listener and permissions:
  ```sh
  ls -l "$HOME/Library/Application Support/Brim/agent.sock"
  log stream --level debug --predicate 'subsystem == "com.harshshelar.brim" AND category == "agent"'
  ```
- Send a test event with the `nc -U` line in [Agent status](#agent-status-m3-f7). If the module is disabled, events are
  dropped rather than buffered.
- `brim://` URLs need the app bundle registered. Launch `build/Brim.app` once; then `open -g 'brim://agent?...'` should
  reach the running app. Percent-encode spaces in `title`/`detail`.
- A Unix socket path has a ~104-byte limit. A very long home directory can exceed it; the log reports “path is too
  long” and the module has no listener. Move the home directory or shorten the path if this happens.
- If an agent crashed, its working/waiting row stays until you dismiss it or press Clear; working sessions do not
  expire automatically.

### Agent alerts do not appear

- Turn on **Settings → General → Agents → Notify when an agent needs input** and leave Agent Status enabled.
- Alerts only fire when a session *newly* enters waiting or failed, and only while no panel is open. A repeated waiting
  event does not alert again.
- The notch alert appears for about 7 seconds under the notch. Look there, not in Notification Center, especially on
  an ad-hoc development build.
- Check the module state:
  ```sh
  log stream --level debug --predicate 'subsystem == "com.harshshelar.brim" AND category == "agent"'
  ```
  A skipped system notification logs the authorization state; the notch fallback still runs.
- **System banners need a signed build.** With the ad-hoc `build/Brim.app`, macOS reports “Notifications are not allowed
  for this application” and never shows a permission prompt. Brim deliberately falls back to its own notch alert.
- If macOS banners are off, Settings offers **Open Settings…** to the Notifications pane; the notch alert remains
  available either way.

### Automation was denied or keeps asking

macOS grants Automation per player and only prompts for a player that is running. Start Spotify or Music, then use
**Settings → General → Grant Automation…**. Ad-hoc rebuilding can reset grants; re-grant after a dev rebuild.

### The panel does not appear on hover

- Check that the pointer reaches the very top edge, inside the notch on a notched display, or the small handle at the
  top center of a display without one.
- Confirm Brim is running: `pgrep -fl '/Brim.app/Contents/MacOS/Brim'`.
- Check the logs:
  `log stream --predicate 'subsystem == "com.harshshelar.brim"'`.
- Settings → General → "Show a handle on displays without a notch" controls non-notched displays only. The notched
  display always has a panel.
- If a full-screen app hides it, macOS may have changed window-level behaviour; see the `NotchWindow` note in
  [`docs/TESTING.md`](docs/TESTING.md).

### Settings window does not open

Use the gear in the expanded panel or right-click → Settings…. While a Brim window is focused, ⌘, also works. Brim is an
agent app, so there is no Dock icon to click.

### A rebuild dropped a permission or login item

`build.sh` signs ad hoc. Every rebuild looks like a new app to macOS, so Automation/Accessibility grants and login-item
registration can be dropped or become stale. Re-grant them in System Settings → Privacy & Security, and toggle launch at
login off/on. A properly signed release build will not have this problem.

### Settings are stuck or malformed

Quit Brim and delete or move `~/Library/Application Support/Brim/settings.json`. Brim writes defaults on the next change.
Unreadable files are backed up next to the original as `settings.corrupt-<timestamp>.json`.

### Idle CPU seems high

The collapsed panel should be near zero: pointer tracking is event-driven and the clock only updates while a panel is
visible. Check `swift test` and the logs for repeated window rebuilds. The manager ignores repeated display notifications
that do not change the screen layout.

## License

[MIT](LICENSE). The bundled MediaRemote helper is BSD-3; its license is included in the app bundle at
`Contents/Resources/MediaAdapter/LICENSE`.
