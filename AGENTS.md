# AGENTS.md

Guide for coding agents working on **Brim**, a native macOS app that turns the MacBook notch into a hover-to-expand
panel. The source of truth for features and acceptance criteria is
[`Brim — macOS Notch Panel Spec.md`](Brim%20%E2%80%94%20macOS%20Notch%20Panel%20Spec.md). Read it before you start.

## Current state

The repository holds only the spec. No code exists yet. Brim copies its project layout from its sibling app
**Speakeasy** (`../speakeasy`, a menu bar manager), which is further along (M1 and M2 shipped). When this file says
"as in Speakeasy", open the named Speakeasy file and copy its pattern. **Copy and adapt the code, never import or
depend on Speakeasy.** The two apps must build, sign and crash independently.

Update this file when the real layout drifts from what's described here.

## Repository layout (target)

```
brim/
├── AGENTS.md
├── Brim — macOS Notch Panel Spec.md   # features, acceptance criteria, risks
├── README.md                          # documentation hub: build/run, code layout, troubleshooting
├── LICENSE
├── Package.swift                      # SwiftPM: Brim (executable), BrimKit (library), BrimTests
├── build.sh                           # builds build/Brim.app and signs it ad hoc
├── .gitignore                         # .build/ build/ *.app .swiftpm/ xcuserdata/ DerivedData/ .DS_Store
├── Resources/
│   └── Info.plist                     # com.harshshelar.brim, LSUIElement = YES, LSMinimumSystemVersion 14.0
├── Sources/
│   ├── Brim/
│   │   └── main.swift                 # only: MainActor.assumeIsolated { BrimLauncher.run() }
│   └── BrimKit/
│       ├── App/                       # composition root: launcher, AppDelegate, AppController, AppModel, WindowPresenter
│       ├── Window/                    # NotchWindow (NSPanel), per-screen window manager, pointer tracking
│       ├── State/                     # hover/expand state machine, timers. Pure logic, no AppKit
│       ├── Modules/                   # BrimModule protocol, module registry, implementations (placeholder, Media, …)
│       ├── Services/                  # Protocols.swift + real implementations (screens, now playing, login item, settings)
│       ├── Model/                     # value types: ScreenInfo, PanelState, NowPlaying, Settings
│       ├── Support/                   # Log.swift (os.Logger categories), Diagnostics.swift
│       └── UI/                        # SwiftUI panel views and settings. Never touches NSPanel
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
| `Package.swift` | `Package.swift` | Same three targets and `.macOS(.v14)`. Brim has **no** dependencies (Speakeasy uses KeyboardShortcuts) |
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
| `Support/Log.swift` | `Support/Log.swift` | `enum Log` with subsystem `com.harshshelar.brim` and categories `general`, `window`, `state`, `media`, `settings` |
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
   login item, settings persistence, permissions). Each has one real implementation and one fake in
   `Tests/BrimTests/Fakes.swift`.
5. **Features are `BrimModule`s.** New functionality (media, calendar, AI tools) goes in `Modules/` and plugs into the
   module host without changes to the window shell.
6. **No permission requests at launch.** A module asks for its permission only when the user enables it, after an
   in-app explanation, and keeps working (degraded) when permission is denied.
7. **No network access in M1 or M2.** No analytics, ever.
8. **No third-party dependencies** without asking the user first.
9. **Idle cost is near zero:** under 0.5% CPU and under 80 MB memory. Prefer notifications to polling, and never poll
   faster than once a second while collapsed. Monitors (pointer, now playing) run only while someone needs them.

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
swift build          # compile
swift test           # unit tests (XCTest, @testable import BrimKit)
./build.sh           # release build → build/Brim.app, signed ad hoc (./build.sh debug for debug)
open build/Brim.app
```

- Requires macOS 14+ and Swift 5.10+. The main test machine is an Apple Silicon MacBook with a notch.
- `build/` and `.build/` are git-ignored. Never commit build output.
- Ad hoc signing means every rebuild looks like a new app to macOS, so granted permissions (Automation, etc.) get
  dropped. Re-grant them in System Settings → Privacy & Security and describe this in the README troubleshooting section.
- Logs: `log stream --predicate 'subsystem == "com.harshshelar.brim"'`.

## Testing expectations

- Unit test: the hover/expand state machine (fake clock), screen and notch geometry (recorded `ScreenInfo` values), the
  module registry, settings migrations, and the media module against a fake `NowPlayingService`.
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

- **MediaRemote is locked down on macOS 15.4+.** Prototype `mediaremote-adapter` first and fall back to Apple Events
  (Spotify and Music.app only). Keep both behind `NowPlayingService`.
- **Window level and full-screen behavior** shift between macOS releases. Keep all window setup in `NotchWindow`.
- **Notch geometry** comes only from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Derive `notchRect` in one place
  and unit test it.
- **Hover can feel twitchy** because the pointer crosses the notch on its way to the menu bar. Use a peek delay, an
  exit area larger than the entry area, and a collapse timer that can be canceled.
