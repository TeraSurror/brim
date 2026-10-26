# Brim — macOS Notch Panel Spec

Oct 25, 2026 · @Harsh Shelar

## Overview

**Brim** is a native macOS app that turns the MacBook notch into a small panel that drops down when you hover over it, in the spirit of NotchNook (getnotchnook.com). The notch is the top edge of the screen, like the brim of a glass, and the name nods to its sibling app, Speakeasy.

This spec is written for a coding agent. Build milestone by milestone; each feature has acceptance criteria that define "done."

**Goals**

- Put glanceable, controllable things (starting with media) right where the pointer already goes: the notch.
- Feel native: SwiftUI content, fluid system-style animations, light and dark mode, near-zero idle CPU.
- Stay modular: the panel hosts pluggable modules, so new features (AI tools, later) slot in without touching the shell.
- Work on screens without a notch too, through a slim handle at the top center.

**Non-goals**

- Mac App Store distribution (MediaRemote and the notch window tricks need APIs outside the sandbox). Run locally, ad hoc signed.
- Supporting macOS versions older than macOS 14 Sonoma.
- Managing menu bar icons. That's Speakeasy's job.

**Why Brim is separate from Speakeasy**

- Speakeasy promises no network access and minimal permissions. Brim needs Now Playing, Automation, and later probably Calendar, Camera, Bluetooth and network access for AI tools.
- Crash isolation: a Brim crash must never leave Speakeasy's hidden menu bar icons stuck off-screen.
- Separate bundle IDs mean rebuilding one ad hoc signed app doesn't drop the other's Accessibility grant.
- The only overlap is screen and notch geometry, which is small enough to copy.

**Platform and stack**

| Item | Choice |
| --- | --- |
| Language | Swift 5.10+ (Swift 6 strict concurrency where practical) |
| UI | SwiftUI for panel content and settings; AppKit (`NSPanel`) for the notch window |
| Min OS | macOS 14 Sonoma; primary target is the current macOS release |
| Hardware | Apple Silicon MacBook with a notch is the primary test machine |
| App type | Agent app: `LSUIElement = YES`, no Dock icon |
| Bundle ID | `com.harshshelar.brim` |
| Dependencies | Prefer none. Ask before adding any |

## Core concept and architecture

Brim owns one borderless, non-activating `NSPanel` per screen. The window sits above the menu bar, centered on the notch, and is sized to the notch when collapsed. Hovering grows it into a rounded black panel that looks like the notch growing downward. SwiftUI draws everything inside; AppKit only positions the window and tracks the pointer.

**Layers**

| Layer | Folder | Responsibility |
| --- | --- | --- |
| Window | `Sources/BrimKit/Window/` | `NotchWindow` (`NSPanel`), per-screen window manager, pointer tracking |
| State | `Sources/BrimKit/State/` | Hover/expand state machine, timers; pure logic, no AppKit |
| Modules | `Sources/BrimKit/Modules/` | `BrimModule` protocol and its implementations (Media first) |
| Services | `Sources/BrimKit/Services/` | Protocols plus real implementations (screens, now playing, login item, settings) |
| UI | `Sources/BrimKit/UI/` | SwiftUI panel views and settings; never touches `NSPanel` |

Each service is a Swift protocol with one real implementation and one fake for tests; the UI never calls a macOS API directly.

**Data model**

| Type | Fields |
| --- | --- |
| `ScreenInfo` | id, frame, notchRect (optional), topInset |
| `PanelState` | `.collapsed`, `.peek`, `.expanded` |
| `BrimModule` | id, title, compact view, expanded view, required permissions, isEnabled |
| `NowPlaying` | title, artist, album, artwork, duration, elapsed, isPlaying, sourceApp |
| `Settings` | hoverDelay, collapseDelay, launchAtLogin, enabledModules, showOnNonNotchedDisplays, schemaVersion |

**Reuse from Speakeasy** (copy and adapt, don't depend on it)

- `Package.swift` layout: executable `Brim` + library `BrimKit` + test target `BrimTests`, macOS 14.
- `build.sh`: builds `build/Brim.app`, copies resource bundles, signs ad hoc.
- `Resources/Info.plist`: `LSUIElement = YES`. Add usage strings only when a feature needs them.
- `Support/Log.swift`: the `os.Logger` category pattern.
- `ScreenInfo` + `notchRect` (Speakeasy `Model/Section.swift`) and the `NSScreen` adapter (Speakeasy `MenuBar/SystemAdapters.swift`), which find the notch with `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
- `LoginItemService`, `SettingsStore`, and the fakes-based testing approach.

## Milestone 1: Notch panel shell

M1 delivers an empty but polished panel: it lives over the notch, opens on hover, closes when the pointer leaves, and hosts a placeholder module. No permissions needed.

**F1. Notch window**

A borderless, non-activating `NSPanel` with level above `.mainMenu`, `collectionBehavior` `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` and a transparent background, centered on `notchRect`.

- [ ] When collapsed, the window lines up exactly with the hardware notch and can't be seen.
- [ ] Never takes keyboard focus or activates Brim when it opens.
- [ ] Appears on every Space and over full-screen apps.
- [ ] Clicks outside the visible panel shape pass through to the menu bar and apps below.

**F2. Hover and expand**

A pure state machine: collapsed → peek on hover → expanded on click or longer hover → collapsed when the pointer leaves, after a delay.

- [ ] Hovering the notch shows a short peek within the hover delay (default 150 ms).
- [ ] Clicking, or hovering longer, opens the full panel with a spring animation.
- [ ] Leaving the panel collapses it after the collapse delay (default 400 ms); coming back cancels the collapse.
- [ ] State machine logic is unit tested with a fake clock.

**F3. Multiple displays and screens without a notch**

- [ ] One window per screen; windows rebuild on `NSApplication.didChangeScreenParametersNotification`.
- [ ] On a screen without a notch, a slim handle at the top center opens the same panel (setting, default on).
- [ ] Plugging in or removing an external display never leaves a stray or misplaced window.

**F4. Module host**

The expanded panel shows enabled modules side by side. `BrimModule` is the extension point for every future feature.

- [ ] A placeholder module (clock or date) renders in compact and expanded layouts.
- [ ] Modules can be enabled, disabled and reordered from settings.
- [ ] A module that needs a permission asks for it only when it's turned on, after an in-app explanation.

**F5. Settings and launch at login**

- [ ] Menu bar-free access: right-clicking the panel opens a menu with Settings and Quit.
- [ ] Settings window: launch at login, hover delay, collapse delay, screens without a notch, modules.
- [ ] Settings persist as versioned JSON in Application Support.

## Milestone 2: Media controls

**F6. Now Playing**

Show what's playing and control it. Behind a `NowPlayingService` protocol with a fake for tests.

Known risk, check first: since macOS 15.4, MediaRemote's now-playing calls refuse apps that don't hold Apple's special permission. Options:
1. The community `mediaremote-adapter` workaround, which runs the calls through the system Perl (it has that permission). Covers every app macOS shows as Now Playing.
2. Apple Events to Spotify and Music.app. Needs the Automation permission and covers only those two apps.

Prototype option 1; fall back to option 2 if it breaks.

- [ ] Compact view: small artwork on the left of the notch and a playing indicator on the right while media plays.
- [ ] Expanded view: artwork, title, artist, progress bar, and previous / play-pause / next buttons.
- [ ] Works with Spotify, Music.app and Safari (YouTube); updates within 1 s of a track change.
- [ ] When nothing is playing, the module hides or shows a quiet empty state.
- [ ] If two apps are playing, the user can pick which one Brim follows.

## Milestone 3: AI tools and IDE integration

M3 starts with local agent status. Quick prompt and send-to-assistant are later features: they need network access and
additional permissions, so they get their own acceptance criteria before implementation.

**F7. Agent status**

Coding tools report what they are doing to Brim over a local Unix socket or a `brim://agent` URL. Every integration is
still a `BrimModule`; this first one needs no permission and no network.

- [ ] A tool can report `working`, `waiting`, `done` or `error` for a session, with an optional title, detail, cost and working directory.
- [ ] The peek shows the most urgent state (waiting, then failed, then working, then done) and hides when there is no activity.
- [ ] The expanded panel lists sessions with agent, title, detail, elapsed time and cost; waiting sessions come first and can be dismissed.
- [ ] Finished and failed sessions expire after the configured retention (default 10 minutes); working and waiting sessions stay until they report again or are cleared.
- [ ] The transport is local only: the socket lives in Application Support with `0600` permissions, accepts only the current user, and is removed when the module is disabled or Brim quits. Malformed, oversized and stale events are ignored.
- [ ] `brim://agent` works while Brim is running and launches it when it is not. The URL parser accepts only the documented fields.
- [ ] Enabling Agent Status starts the listener; disabling it stops the listener and clears the roster. No permission prompt appears at launch or when the module is enabled.
- [ ] Settings schema 3 stores the retention period and migrates schema 2 files without losing values.
- [ ] Claude Code is documented as the reference integration; the same contract works for Codex, Cursor, VS Code and any tool that can write one JSON line or open a URL.

**F8. Agent alerts and project actions**

Agent alerts are opt-in, local, and never requested at launch.

- [ ] A session that newly enters `waiting` or `error` while no panel is open produces one alert; repeated events in the same state do not repeat it, and a transition back through working can alert again.
- [ ] Alerts use a macOS notification when the build has permission, and Brim's own notch card otherwise. The notch card is non-activating, auto-dismisses, and carries the same title/body.
- [ ] Clicking an alert or the folder button on an agent row opens the session's `cwd` in Finder. Rows without a path have no folder action.
- [ ] Enabling alerts shows an in-app explanation before any system permission request; denial leaves the notch alert working.
- [ ] Settings schema 4 stores the opt-in flag and migrates older files without losing values.
- [ ] Diagnostics include the alert setting and authorization state.

**Later M3 features (not designed yet)**

- **Quick prompt.** A text box in the expanded panel that sends a prompt to a chosen assistant. Needs per-provider
  network access, API keys in the Keychain and an explicit opt-in flow.
- **Send to assistant.** Drop a file on the notch, or send the current selection or a screenshot, to an assistant.
  Needs drag/drop plus Screen Recording or Accessibility permissions depending on the source.

Each integration ships as a `BrimModule`.

## Stretch goals

Build these only after M2 is stable; each is independent.

- **S1. File tray.** Drop files on the notch to park them; drag them back out or AirDrop them.
- **S2. Calendar.** Upcoming events via EventKit with meeting join buttons.
- **S3. Speakeasy integration.** Show Speakeasy's hidden menu bar icons in the panel, talking to Speakeasy through its planned `speakeasy://` URL scheme or system-wide notifications. No shared code.
- **S4. Volume and brightness display.** Replace the system on-screen display with one drawn from the notch.

## Non-functional requirements

| Area | Requirement |
| --- | --- |
| Performance | Under 0.5% CPU when idle; under 80 MB memory. No polling faster than 1 s while collapsed; prefer notifications. |
| Responsiveness | Hover-to-peek under 100 ms after the delay; animations at display refresh rate. |
| Permissions | Never at launch. Each module requests its own permission when enabled, after an in-app screen explaining why. Degrade gracefully when denied. |
| Privacy | No network access in M1 and M2. Any network use (M3) is per module, opt-in, and documented. No analytics. |
| Persistence | Settings stored as JSON in Application Support, versioned with a schema number and migrations. |
| Multi-display | Correct behavior when displays are added, removed or rearranged while running. |
| Accessibility | Panel controls have VoiceOver labels; settings usable with keyboard only. |
| Logging | `os.Logger` with categories (window, state, media); a "Copy diagnostics" button in settings. |

## Technical notes, risks, and agent instructions

**Known risks**

| Risk | Why | Mitigation |
| --- | --- | --- |
| MediaRemote locked down | macOS 15.4+ refuses now-playing calls from apps without Apple's permission | `mediaremote-adapter` first, Apple Events fallback; keep it behind `NowPlayingService` |
| Window sits above the menu bar | Window levels and full-screen behavior change between macOS releases | Keep window setup in one `NotchWindow` type; test on each new macOS beta |
| Notch geometry | `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the only public hints | Derive `notchRect` in one place; unit test with recorded screen values |
| Hover feels twitchy | Pointer crosses the notch on the way to the menu bar | Peek delay, larger exit area than entry area, cancelable collapse timer |
| Ad hoc signing | Every rebuild looks like a new app and drops granted permissions | Document re-granting in the README troubleshooting section |

**Testing**

- Unit tests for the state machine (fake clock), screen and notch geometry, the module registry, settings migrations, and the media module against a fake `NowPlayingService`.
- Manual checklist per milestone on a notched MacBook, with and without an external display, in light and dark mode, and over a full-screen app.
- Check idle CPU in Activity Monitor after each milestone.

**Instructions for the coding agent**

1. Build one milestone at a time, in order. Do not start M2 until every M1 acceptance box is met.
2. Before writing code for a milestone, propose the file list and protocols and wait for approval.
3. Keep AppKit window code in `Window/`; SwiftUI views must not touch `NSPanel` directly.
4. Put every system API behind a protocol (screens, pointer events, now playing, login item) so it can be faked in tests.
5. Never request a permission at launch. Request it from the module that needs it.
6. After each feature, list how to manually verify it, mapped to its acceptance criteria.
7. Ask before adding any third-party dependency.
8. Use `Brim` as the product name and `com.harshshelar.brim` as the bundle ID.
