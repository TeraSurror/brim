# AGENTS.md

Guide for coding agents working on **Brim**, a native macOS app that turns the MacBook notch into a hover-to-expand
panel. The source of truth for features and acceptance criteria is
[`Brim — macOS Notch Panel Spec.md`](Brim%20%E2%80%94%20macOS%20Notch%20Panel%20Spec.md). Read it before you start.

## Current state

M1, M2, M3 F7/F8 and the UX revision F9–F13 are implemented: the notch panel shell (F1–F5), the clock and Now Playing
modules, agent status over a local Unix socket and `brim://` URL (F7), opt-in agent alerts (F8), and the live notch
revision — hover/click to open with no peek (F9), live activity in the notch's ears (F10), alerts that switch to the
agent's app (F11), first-run setup and the Claude Code hook installer (F12), and a panel that widens per module (F13).
Settings are schema 5. 247 unit tests pass; the UX revision is not committed yet. [`docs/PROGRESS.md`](docs/PROGRESS.md) is the handoff between sessions — read it after the spec. Visual
sign-off for M1, the real-player/two-player sign-off for M2, the real-Claude-Code-hook/visual sign-off for F7, the
signed-build banner/visual sign-off for F8 and the F9–F13 manual rows are still pending; the checklist is
[`docs/TESTING.md`](docs/TESTING.md).
The next M3 features (quick prompt, send-to-assistant) are not designed; brainstorm with the user before writing
acceptance criteria.

Brim copies its project layout from its sibling app **Speakeasy** (`../speakeasy`, a menu bar manager), which is further
along (M1 and M2 shipped). When this file says "as in Speakeasy", open the named Speakeasy file and copy its pattern.
**Copy and adapt the code, never import or depend on Speakeasy.** The two apps must build, sign and crash independently.

Update this file when the real layout drifts from what's described here.

## Repository layout (target)

```
brim/
├── AGENTS.md
├── Brim — macOS Notch Panel Spec.md   # features, acceptance criteria, risks
├── README.md                          # documentation hub: build/run, code layout, troubleshooting
├── LICENSE
├── Package.swift                      # SwiftPM: Brim (executable), BrimKit (library), BrimTests
├── build.sh                           # builds build/Brim.app, bundles the media helper and signs ad hoc
├── scripts/
│   └── build-media-adapter.sh         # pinned MediaRemote adapter build (BSD-3, output in .build/)
├── .gitignore                         # .build/ build/ *.app .swiftpm/ xcuserdata/ DerivedData/ .DS_Store
├── Resources/
│   └── Info.plist                     # com.harshshelar.brim, LSUIElement = YES, LSMinimumSystemVersion 14.0
├── Sources/
│   ├── Brim/
│   │   └── main.swift                 # only: MainActor.assumeIsolated { BrimLauncher.run() }
│   └── BrimKit/
│       ├── App/                       # composition root: launcher, AppDelegate, AppController, AppModel, WindowPresenter
│       ├── Window/                    # NotchWindow (NSPanel), per-screen window manager, pointer tracking, notch alert
│       ├── State/                     # hover/expand state machine, timers, live-activity priority, agent roster/alert
│       │                              #   geometry. Pure logic, no AppKit
│       ├── Modules/                   # BrimModule protocol, module registry, implementations (Clock, Media, Agent…)
│       ├── Services/                  # Protocols.swift + real implementations (screens, now playing, login item,
│       │                              #   settings, MediaRemote helper, Spotify/Music Apple Events, agent socket/URL,
│       │                              #   local notifications, opening a session's app/folder, Claude Code hook installer)
│       ├── Model/                     # value types: ScreenInfo, PanelState, LiveActivity, NowPlaying, AgentEvent/Notification, Settings
│       ├── Support/                   # Log.swift (os.Logger categories), Diagnostics.swift
│       └── UI/                        # SwiftUI panel views, media/agent cards, notch alert and settings. Never touches NSPanel
├── Tests/
│   └── BrimTests/
│       ├── Fakes.swift                # every fake in one file
│       └── *Tests.swift               # one file per unit under test
└── docs/
    ├── TESTING.md                     # manual checklist per milestone + known limitations
    └── USAGE.md                       # user guide (added once there is something to use)
```

The spec's layer table lists `Window/`, `State/`, `Modules/`, `Services/` and `UI/`. `App/`, `Model/` and `Support/`
come from Speakeasy and hold the composition root, plain data types and logging.

### Speakeasy → Brim mapping

| Speakeasy | Brim | Notes |
| --- | --- | --- |
| `Package.swift` | `Package.swift` | Same three targets and `.macOS(.v14)`. No SwiftPM dependencies (Speakeasy uses KeyboardShortcuts); the MediaRemote helper is a separately built, user-approved third-party binary under `scripts/` |
| `build.sh` | `build.sh` | Swap the names. Keep the `*.bundle` copy loop only if a dependency or resource bundle appears |
| `Resources/Info.plist` | `Resources/Info.plist` | Bundle ID `com.harshshelar.brim`. Add usage strings only when a feature needs them |
| `Sources/Speakeasy/main.swift` | `Sources/Brim/main.swift` | Calls the launcher, nothing else |
| `App/SpeakeasyApp.swift` | `App/BrimApp.swift` | `NSApplication` + `AppDelegate` + `.accessory` policy, **not** the SwiftUI `App` lifecycle (its `Settings` scene opens an empty window). Keep the hidden main menu so ⌘C/⌘V/⌘W/⌘Q work in settings windows |
| `App/AppController.swift` | `App/AppController.swift` | Composition root: builds the real services and wires them together |
| `App/AppModel.swift` | `App/AppModel.swift` | `@MainActor ObservableObject`. Saves settings in `didSet` when they change |
| `App/WindowPresenter.swift` | `App/WindowPresenter.swift` | Owns the settings window (`NSWindow` + `NSHostingController`) |
| `MenuBar/` | `Window/` | All AppKit window code lives here, and only here |
| `MenuBar/RehideTimer.swift`, `SectionController.swift` | `State/` | Timer-driven logic over `Scheduling`, testable with `FakeScheduler` |
| `MenuBar/SystemAdapters.swift` | `Services/` (or `Window/`) | `DispatchScheduler`, `NSScreenProvider` (finds the notch via `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` / `safeAreaInsets.top`) |
| `Model/Section.swift` → `ScreenInfo` | `Model/ScreenInfo.swift` | Copy the computed `notchRect` logic. Use CoreGraphics global space (origin top-left of the primary display) |
| `Model/Settings.swift` | `Model/Settings.swift` | `currentSchemaVersion` plus a custom `init(from:)` using `decodeIfPresent ?? default` so old files still load |
| `Services/Protocols.swift` | `Services/Protocols.swift` | Every system-facing protocol in one file, plus `TaskHandle` and `Scheduling` |
| `Services/SettingsStore.swift` | `Services/SettingsStore.swift` | `SettingsMigrator` (step per version) + `JSONSettingsStore` in `~/Library/Application Support/Brim/settings.json`. Corrupt files are moved aside, not deleted |
| `Services/LoginItemService.swift` | `Services/LoginItemService.swift` | `SMAppService.mainApp` behind `LoginItemControlling` |
| `Support/Log.swift` | `Support/Log.swift` | `enum Log` with subsystem `com.harshshelar.brim` and categories `general`, `window`, `state`, `media`, `settings`, `agent` |
| `Support/Diagnostics.swift` | `Support/Diagnostics.swift` | Text report for the "Copy diagnostics" button: version, macOS, screens + notch rects, settings JSON |
| `Tests/SpeakeasyTests/Fakes.swift` | `Tests/BrimTests/Fakes.swift` | `FakeScheduler` (a fake clock with `advance(by:)`), `FakeScreens`, plus Brim's own (`FakeNowPlaying`, …) |
| `docs/TESTING.md` | `docs/TESTING.md` | A table per milestone, one row per feature (F1, F2, …) |

## Architecture rules

These come from the spec's "Instructions for the coding agent" and Speakeasy's code. They are not optional.

1. **One `NSPanel` per screen**, owned by the window manager in `Window/`. Rebuild windows on
   `NSApplication.didChangeScreenParametersNotification`.
2. **AppKit stays in `Window/`** (and the `App/` composition root). SwiftUI views in `UI/` never touch `NSPanel`,
   `NSScreen` or other AppKit window APIs.
3. **`State/` is pure logic.** No AppKit imports. Time comes from an injected `Scheduling`, so tests drive it with
   `FakeScheduler`.
4. **Every system API sits behind a protocol** in `Services/Protocols.swift` (screens, pointer events, now playing,
   login item, settings persistence, permissions, agent event listening). Each has one real implementation and one fake in
   `Tests/BrimTests/Fakes.swift`.
5. **Features are `BrimModule`s.** New functionality (media, calendar, AI tools) goes in `Modules/` and plugs into the
   module host without changes to the window shell. A module shows itself at rest by publishing a `LiveActivity` and
   drawing its two ear views; the shell only picks the highest priority.
6. **No permission requests at launch.** A module asks for its permission only when the user enables it, after an
   in-app explanation, and keeps working (degraded) when permission is denied.
7. **No network access in M1 or M2.** Agent status (M3 F7) is local-only as well. No analytics, ever. Any later network
   use (quick prompt) is per module, opt-in, and documented.
8. **No third-party dependencies** without asking the user first. The one approved exception is the build-time MediaRemote helper (BSD-3, pinned by tag and SHA, never linked or committed).
9. **Idle cost is near zero:** under 0.5% CPU and under 80 MB memory, counting Brim's helper processes. Prefer
   notifications to polling, and never poll faster than once a second while collapsed (a followed player is polled every
   3 s then). Monitors (pointer, now playing) run only while someone needs them. The agent socket is one file descriptor
   while its module is enabled; its roster prunes on events/panel open, not a timer.
10. **Media stays behind `NowPlayingProviding`.** The MediaRemote helper is a child process loaded by Perl, never
    linked into Brim. It runs while Now Playing is enabled and the live notch is on (otherwise only while a panel is
    open, plus a one second grace), restarts with a backoff if it exits, and is wrapped in a supervisor that watches
    Brim's PID so it cannot outlive the app.
11. **Player control is optional.** The helper needs no permission. Following Spotify or Music directly is an
    Automation feature requested through the module's explanation flow; denial must leave the adapter path working.
12. **Agent events stay local.** The Unix socket lives in Application Support with a `0700` directory and `0600` file,
    rejects other users with `getpeereid`, and is removed when the module is disabled or Brim quits. `brim://agent`
    input is validated as untrusted; never execute a field from it. The `app` field is only ever looked up as an
    installed bundle identifier. Brim edits `~/.claude/settings.json` only from the Settings button, after showing what
    changes, with a backup, and never when the file does not parse. Enabling Agent Status is the only switch that
    starts the listener — no permission prompt is involved. Agent alerts are a separate opt-in; when macOS refuses
    notification authorization (notably ad-hoc dev builds), use the notch alert rather than silently dropping the alert.

## Code conventions (as in Speakeasy)

- Swift 5.10 tools, Swift 6 strict concurrency where practical. UI-facing types and protocols are `@MainActor`.
  Value types are `Sendable` and usually `Equatable`.
- `BrimKit` types used by the app target or tests are `public`, with explicit `public init`s.
- Inject dependencies through initializers, with real implementations as default arguments where that helps
  (`init(screens: ScreenProviding = NSScreenProvider())`).
- Testable pure logic goes in `static func`s split out of the AppKit-facing type (see `WindowListItemService.items(from:)`).
- Doc comments (`///`) explain *why* or non-obvious macOS behavior, not what the code does. Keep them short.
- Log through `Log.<category>`, never `print`.
- Settings changes need a schema bump and a `SettingsMigrator` step, plus a test.

## Build, run, test

```sh
swift build          # compile (no media helper needed)
swift test           # unit tests (XCTest, @testable import BrimKit)
./build.sh           # release build → build/Brim.app, signed ad hoc (./build.sh debug for debug)
open build/Brim.app
```

- Requires macOS 14+ and Swift 5.10+. The main test machine is an Apple Silicon MacBook with a notch.
- `./build.sh` also builds the MediaRemote helper on first use: it needs **CMake** and network access to clone the
  pinned tag into `.build/media-adapter-src`. `swift test` and `swift build` do not. Use
  `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh` for an app without media; the rest of Brim still runs.
- No media is playing in an automated environment, so test the helper with its `test` command and the manual media
  checks in [`docs/TESTING.md`](docs/TESTING.md), or point `BRIM_MEDIA_ADAPTER_PATH` at a stub adapter for UI work.
- `build/` and `.build/` are git-ignored. Never commit build output.
- Ad hoc signing means every rebuild looks like a new app to macOS, so granted permissions (Automation, etc.) get
  dropped. Re-grant them in System Settings → Privacy & Security and describe this in the README troubleshooting section.
- Logs: `log stream --predicate 'subsystem == "com.harshshelar.brim"'`.

## Testing expectations

- Unit test: the hover/expand state machine (fake clock), screen, notch and live-notch geometry (recorded `ScreenInfo`
  values), live-activity priority, the module registry, settings migrations, the media module against a fake
  `NowPlayingService`, and agent event validation, roster ordering/retention, notification transitions/geometry, the
  socket listener against a real temp socket, URL parsing, and the Claude Code hook installer against a temp home.
- Each test file covers one unit, is a `@MainActor final class …Tests: XCTestCase` and builds its fakes in `setUp`.
- After each feature, add a row to `docs/TESTING.md` that maps manual checks to that feature's acceptance criteria:
  notched MacBook, with and without an external display, light and dark mode, over a full-screen app. Check idle CPU in
  Activity Monitor after each milestone.

## Workflow

1. Build milestones **in order** (M1 shell → M2 media → M3 AI tools → stretch goals). Don't start the next milestone
   until every acceptance box in the current one is checked.
2. **Before writing code for a milestone, propose the file list and protocols and wait for the user's approval.**
3. Implement feature by feature (F1, F2, …). Keep commits scoped to one feature and name the feature in the commit
   message, as Speakeasy does (`F10 layout screen; …`, `Milestone 2: …`).
4. After each feature, list the manual checks for its acceptance criteria and run `swift test`.
5. M3 (AI tools and IDE integration) isn't designed yet. Brainstorm with the user before writing its acceptance criteria.

## Known risks to keep in mind

- **MediaRemote is locked down on macOS 15.4+.** Brim bundles `ungive/mediaremote-adapter` v0.7.7 (BSD-3, user
  approved), built from a pinned SHA by `scripts/build-media-adapter.sh`; the helper prints JSON through
  `/usr/bin/perl`. The `test` command detects a future break. Fall back to Apple Events (Spotify and Music.app only)
  via `PlayerAutomationService`; keep both behind `NowPlayingProviding`.
- **The helper is private-API dependent.** Do not link its framework into Brim, do not commit its binaries, and bump
  the pinned tag only after running the `test` command and the manual media checks on the current macOS.
- **Window level and full-screen behavior** shift between macOS releases. Keep all window setup in `NotchWindow`.
- **Notch geometry** comes only from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Derive `notchRect` in one place
  and unit test it.
- **Hover can feel twitchy** because the pointer crosses the notch on its way to the menu bar. Use a peek delay, an
  exit area larger than the entry area, and a collapse timer that can be canceled.
