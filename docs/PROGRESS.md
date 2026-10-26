# Brim — build progress

This file is the handoff between sessions. Read it with `AGENTS.md` and the spec before touching code, and update it
before ending a session.

**Last updated:** 2026-10-25
**Current milestone:** M3 — agent status (F7), code complete; manual sign-off pending
**Next action:** run the M1, M2 and M3 manual checks in [`TESTING.md`](TESTING.md). Then design the next M3 feature
(quick prompt or send-to-assistant) before writing its acceptance criteria.

## How to resume

1. Read `AGENTS.md`, then `Brim — macOS Notch Panel Spec.md`, then this file.
2. `swift test` and `./build.sh && open build/Brim.app` to confirm the tree still builds.
3. If M1/M2/M3 still have unchecked manual checks, do those first. Otherwise pick the next feature.
4. One feature at a time (F8, F9, …), one commit per feature.
5. Before ending a session: tick boxes here, add manual results to `docs/TESTING.md`, add an entry to **Session log**,
   and update `AGENTS.md` → **Current state** if the layout changed.

## Status at a glance

| Milestone | State |
| --- | --- |
| M1 — Notch panel shell | Code complete (F1–F5), 47 unit tests pass, manual visual sign-off pending |
| M2 — Media controls | Code complete (F6), 100 unit tests pass, real-player and visual sign-off pending |
| M3 — AI tools and IDE integration | F7 (agent status) code complete; 157 unit tests pass; manual sign-off pending. Quick prompt and send-to-assistant are not designed |
| Stretch goals | Not started |

Test machine: macOS 26.6.2, Apple Silicon. Displays seen during development: primary 1920×1080 (no notch) and built-in
1470×956 with a 179×32 notch. Minimum target remains macOS 14.

## M3 — what exists

F7 adds a local agent-status channel without touching the window shell or requiring a permission:

```
Sources/BrimKit/Model/AgentEvent.swift             status, validated event, session, wire JSON decoder
Sources/BrimKit/State/AgentRoster.swift            pure aggregation, urgency order, retention, session cap
Sources/BrimKit/Services/AgentSocketService.swift  POSIX Unix-socket listener, JSON lines, same-user check
Sources/BrimKit/Services/AgentURLRouter.swift      pure brim://agent URL parser
Sources/BrimKit/Modules/AgentModule.swift          listener lifecycle, roster, retention
Sources/BrimKit/UI/AgentCompactView.swift          peek: status glyph, agent/headline, count
Sources/BrimKit/UI/AgentExpandedView.swift         card: session rows, cost, elapsed, dismiss/clear
```

Changed: `Protocols` has `AgentEventListening`; `AppController` builds the module and routes URLs; `BrimApp` handles
`application(_:open:)` and terminates the listener on quit; `AppModel` exposes the socket path/retention and clears
finished sessions; `Settings` is schema 3 with `agentFinishedRetentionMinutes`; `SettingsStore` has the step;
`Diagnostics` includes listener status and session counts; `SettingsView` has an Agents section; `Info.plist`
registers the `brim` URL scheme; `Log` gains the `agent` category.

Tests: `AgentEventTests`, `AgentRosterTests`, `AgentSocketServiceTests` (real temp socket, malformed/oversized input),
`AgentURLRouterTests`, `AgentModuleTests`, plus schema-3 and AppModel retention/clear tests. 157 tests total.

The Claude Code hook is documented in [`TESTING.md`](TESTING.md) and the README; the generic contract is any executable
that writes one JSON object per line to the socket or opens a `brim://agent?...` URL.

## M2 — what exists

M2 adds a Now Playing module without touching the window shell's pointer/animation logic:

```
Sources/BrimKit/Model/NowPlaying.swift             track, source, artwork hash, position interpolation
Sources/BrimKit/Services/NowPlayingService.swift   NowPlayingProviding protocol
Sources/BrimKit/Services/NowPlayingCoordinator.swift  preference, fallback, 1 s poll, helper lifecycle
Sources/BrimKit/Services/MediaAdapterParser.swift  pure stream/diff JSON decoder
Sources/BrimKit/Services/MediaAdapterService.swift Perl helper + shell supervisor + one-shot commands
Sources/BrimKit/Services/PlayerAutomationService.swift  Spotify/Music Apple Events read/control/discovery
Sources/BrimKit/Services/AutomationPermission.swift  AEDeterminePermissionToAutomateTarget wrapper
Sources/BrimKit/Modules/MediaModule.swift          BrimModule + MediaModuleControlling
Sources/BrimKit/UI/MediaCompactView.swift          peek: artwork left, title, indicator right
Sources/BrimKit/UI/MediaExpandedView.swift         card: artwork, metadata, slider, transport, source menu
Sources/BrimKit/UI/MediaArtworkView.swift          decode/cache artwork by content hash
Sources/BrimKit/UI/EqualizerIndicator.swift        playing/paused indicator
scripts/build-media-adapter.sh                     pinned MediaRemote adapter build (BSD-3, not committed)
```

Changed: `BrimModule` gained `setPanelActive` and `expandedLayoutPriority`; `ModuleRegistry` forwards the panel
lifecycle; `AppModel` aggregates open panels across screens, persists the followed player, and reports Automation
status; `NotchWindowController` reports active only from the first peek until the collapse animation ends;
`Settings` is schema 2 with `preferredPlayerBundleID`; `SystemPermissionService` implements `.automation`;
`PanelView` splits the width evenly between enabled modules; the media card adapts below 320 pt by hiding the album
and collapsing the source menu. Settings has a Media section; diagnostics
include helper/track lines; `build.sh` bundles the helper and the Info.plist explains Apple Events.

Tests: `MediaAdapterParserTests`, `MediaAdapterServiceTests` (real Perl stub process), `NowPlayingCoordinatorTests`,
`MediaModuleTests`, `NowPlayingTests`, plus schema-2, AppModel panel/preference tests.

## M1 — what exists

```
Package.swift                 Brim executable + BrimKit library + BrimTests, no dependencies, macOS 14
build.sh                      build/Brim.app, ad-hoc signed
Resources/Info.plist          com.harshshelar.brim, LSUIElement
Sources/Brim/main.swift       launcher only

Sources/BrimKit/App/
  BrimApp.swift               NSApplication + AppDelegate + hidden main menu + launcher
  AppController.swift         composition root (services → model → window manager)
  AppModel.swift              settings, launch at login, module enable + permission gate, diagnostics
  WindowPresenter.swift       settings window, centered on the screen under the pointer

Sources/BrimKit/Model/
  ScreenInfo.swift            id, CG frame, auxiliary widths, topInset, derived notchRect
  PanelState.swift            collapsed / peek / expanded
  Settings.swift              schema version 1 + tolerant decoding with clamped delays
  Permission.swift            PermissionKind / PermissionStatus

Sources/BrimKit/State/        pure logic, no AppKit
  PanelGeometry.swift         panel/hit rects per state, notched and plain screens, PanelTimings
  PanelStateMachine.swift     hover → peek → expanded → collapse, cancelable timers

Sources/BrimKit/Modules/
  BrimModule.swift            id, title, symbol, permissions, enabled, compact/expanded views
  ModuleRegistry.swift        enabled/ordered subset, unknown + duplicate IDs filtered
  ClockModule.swift           placeholder module (minute clock)

Sources/BrimKit/Services/
  Protocols.swift             TaskHandle, Scheduling, ScreenProviding, PointerMonitoring,
                              LoginItemControlling, SettingsPersisting, PermissionRequesting
  SystemAdapters.swift        DispatchScheduler, NSScreenProvider
  LoginItemService.swift      SMAppService.mainApp
  SettingsStore.swift         SettingsMigrator + JSONSettingsStore
  PermissionService.swift     placeholder until M2 wires real permissions

Sources/BrimKit/Window/       AppKit window code only
  NotchWindow.swift           borderless, non-activating panel above the menu bar
  NotchWindowController.swift one screen: state machine, hosting view, frame animation, tracking area
  NotchWindowManager.swift    one window per eligible screen; rebuild on display changes
  PanelHostingView.swift      NSHostingView with inactive-app hover tracking
  PointerMonitor.swift        global + local NSEvent mouse monitor

Sources/BrimKit/Support/
  Log.swift                   subsystem com.harshshelar.brim
  Diagnostics.swift           version, macOS, screens/notches, settings JSON, recent log

Sources/BrimKit/UI/           SwiftUI only
  PanelView.swift             collapsed handle, peek strip, expanded module host, context menu
  NotchPanelShape.swift       top-attached shape with rounded bottom corners
  PanelStateModel.swift       per-window ObservableObject for the state
  SettingsView.swift          General / Modules / About
  PermissionExplanationView.swift  pre-permission sheet

Tests/BrimTests/              47 tests, all passing
  Fakes.swift, ScreenInfoTests, PanelGeometryTests, PanelStateMachineTests,
  ModuleRegistryTests, SettingsTests, AppModelTests

docs/TESTING.md               manual checklist per feature + known limitations
```

## M1 acceptance checklist

`[x]` means implemented and covered by an automated check or verified against the running app. Visual checks that
could not be automated are listed under **Manual sign-off still needed**.

### F1. Notch window

- [x] Borderless, non-activating `NSPanel`, level above `.mainMenu`, `[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`, transparent background, centered on `notchRect`.
- [x] Collapsed window lines up exactly with the hardware notch and can't be seen. (Window bounds are exactly the notch; the SwiftUI content is `Color.clear` and the window alpha is 0 on notched screens, verified as `kCGWindowAlpha=0`.)
- [x] Never takes keyboard focus or activates Brim when it opens. (`canBecomeKey`/`canBecomeMain` false, `.nonactivatingPanel`.)
- [x] Appears on every Space and over full-screen apps. (Collection behavior set; full-screen sign-off pending.)
- [x] Clicks outside the visible panel shape pass through. (The window frame is always exactly the visible panel rect.)

### F2. Hover and expand

- [x] Hovering the notch shows a short peek within the hover delay (default 150 ms).
- [x] Clicking, or hovering longer, opens the full panel with a spring animation. (The frame grows with an ease-out; the peek stays visible while the window grows, then the expanded layout fades/lifts in at full size.)
- [x] Leaving the panel collapses it after the collapse delay (default 400 ms); coming back cancels the collapse.
- [x] State machine logic is unit tested with a fake clock.

### F3. Multiple displays and screens without a notch

- [x] One window per screen; windows rebuild on `NSApplication.didChangeScreenParametersNotification`. Duplicate launch-time notifications are ignored when the screen signature is unchanged.
- [x] On a screen without a notch, a slim handle at the top center opens the same panel (setting, default on).
- [x] Plugging in or removing an external display never leaves a stray or misplaced window. (Rebuild closes controllers whose screen disappeared; hot-plug sign-off pending.)

### F4. Module host

- [x] The expanded panel shows enabled modules side by side. (Only the clock exists in M1.)
- [x] A placeholder module (clock) renders in compact and expanded layouts.
- [x] Modules can be enabled, disabled and reordered from settings.
- [x] A module that needs a permission asks for it only when it's turned on, after an in-app explanation. (Flow implemented and unit tested with a fake module; no M1 module needs a real permission, so M2 will exercise it.)

### F5. Settings and launch at login

- [x] Right-clicking the panel opens a menu with Settings and Quit. (Verified: a layer-101 menu appeared and Settings opened.)
- [x] Settings window: launch at login, hover delay, collapse delay, screens without a notch, modules.
- [x] Settings persist as versioned JSON in Application Support. (Verified: toggling the non-notched handle and enabling/disabling the clock wrote `~/Library/Application Support/Brim/settings.json`.)
- [x] Copy diagnostics and Quit are reachable from settings; keyboard-only usable. (Copy Diagnostics verified on the clipboard; keyboard-only sign-off pending.)

### Non-functional checks for M1

- [x] Idle CPU under 0.5% and memory under 80 MB. (Measured 0.0% CPU; ~22 MB RSS in debug, ~50 MB in release after warm-up.)
- [x] No permission prompt at launch; no network use. (No permission APIs are called and no networking code exists.)
- [x] Logs appear under subsystem `com.harshshelar.brim`.
- [ ] Light/dark mode, external display, full-screen app visually checked. (External display behavior verified programmatically; visual appearance still pending.)

## M2 acceptance checklist

- [x] **Compact view**: artwork on the left, title/artist and a playing indicator on the right while media plays.
  (Verified in an offscreen render and the real accessibility tree with a stub adapter; real artwork needs a player.)
- [x] **Expanded view**: artwork, title, artist, album, progress bar, previous / play-pause / next. The slider seeks.
  (Accessibility tree: slider value advanced from 30 to 37.3 s while the stub played; time labels 0:37 / -2:23;
  AXPress on Next/Pause produced adapter `send 4` / `send 2`.)
- [x] **Spotify, Music and Safari; updates within 1 s.** The adapter covers all system Now Playing apps; the stream is
  push-based and the parser applies diffs. `test` exits 0 on macOS 26.6.2. Real Spotify/Music/Safari playback could not
  be exercised here (nothing was playing; Spotify is not installed), so this remains a manual check.
- [x] **Nothing playing**: the compact view disappears and the expanded card shows a quiet empty state.
- [x] **Two players**: Follow (Settings and the in-panel source menu) persists a preferred player; Automatic is the
  fallback. Covered by coordinator tests with fakes; needs Spotify + Music for the real two-player sign-off.
- [x] **Permission flow**: the module declares Automation, explains it before the system prompt, enables in a degraded
  adapter-only form when denied, and never prompts at launch. Real prompts were not triggered in this session.
- [x] **Idle/lifecycle**: the helper starts only on peek/expand and stops after the one-second grace; a shell supervisor
  kills it if Brim is quit, crashes or is `kill -9`ed. Verified with `pgrep` before/after. Release idle measured at
  0.0% CPU and ~33 MB RSS after warm-up, under the 80 MB budget.
- [x] **Settings**: schema 2 migration keeps old files, the followed player round-trips, and the picker is keyboard
  accessible. Unit tested.
- [x] **Diagnostics** include helper availability, followed player and current track.

## M3 F7 acceptance checklist

- [x] **Event contract**: an integration reports `working`, `waiting`, `done` or `error`, with optional title, detail,
  cost and working directory. `AgentEvent` trims/truncates text, rejects empty identities and invalid costs, and the
  socket/URL decoders drop malformed input. Unit tested.
- [x] **Transports**: JSON lines over `~/Library/Application Support/Brim/agent.sock` and `brim://agent?...` URLs both
  reach the module. Verified against the running app with a Python socket client and `open -g`; the AX tree showed the
  sessions.
- [x] **Peek**: shows the most urgent state and hides when the roster is empty. Waiting sorts before failed, working and
  done; the compact view names a single agent or counts several. Unit tested and seen in the running panel.
- [x] **Expanded card**: lists agent, title, detail, elapsed time and cost; waiting rows are tinted and first; each row
  has a dismiss button and finished rows can be cleared. Verified in the accessibility tree.
- [x] **Retention**: done/failed sessions expire after the configured period (default 10 minutes); working/waiting
  sessions are never auto-expired. Pruning happens on events and panel open, not on a timer. Unit tested.
- [x] **Local-only transport**: the socket directory is `0700`, the socket is `0600`, `getpeereid` rejects other users,
  and the file is removed when the module is disabled or Brim quits. Verified permissions and quit cleanup against the
  app; malformed and oversized lines are covered by the real-socket tests.
- [x] **URL handling**: works while Brim is running and when it is launched by the URL; `dismiss` and `clear` actions
  update the roster. Verified with `open -g` in both states.
- [x] **Lifecycle**: enabling the module starts the listener, disabling stops it and clears sessions; a launch with the
  module already enabled starts the listener. Unit tested.
- [x] **Settings schema 3**: retention round-trips, schema 2 files migrate without losing values, and the retention
  value is clamped. Unit tested.
- [x] **No permissions / no network**: the module declares no permissions, never prompts, and has no networking code.
- [ ] **Manual visual sign-off**: light/dark mode, a long session list, and the card beside clock + media on the notched
  display. See [`TESTING.md`](TESTING.md).

## Manual sign-off still needed

These need a human at the screen; this environment could not take screenshots (no Screen Recording permission for the
agent process). Run through [`TESTING.md`](TESTING.md).

- Does the collapsed notched window really disappear behind the hardware notch?
- Does the panel look right in light and dark mode, and does the peek read as the notch growing?
- Does it appear over a full-screen app and on every Space?
- Hot-plugging an external display: no stray window, and the notched screen keeps its panel.
- Keyboard-only use of settings and VoiceOver labels on panel controls.
- Launch at login against the real `SMAppService` (toggling it in a dev build may register the ad-hoc app; toggle back off afterwards).
- Idle CPU in Activity Monitor with the panel collapsed after the app has been open for a while.
- M2: real Spotify/Music/Safari media, artwork, <1 s track changes, and two players playing at once (Spotify is not
  installed on the development machine).
- M2: the Automation prompt and its denied state against the real system dialogs.
- M2: the expanded media card next to the clock at 600×320 on the notched MacBook, in light and dark mode.
- M3: the Agent Status card beside clock and media, in light and dark mode, with enough sessions to scroll.
- M3: the documented Claude Code hook with a real Claude Code session (permission prompt → waiting, stop → done).
- M3: keyboard/VoiceOver use of the session dismiss and clear controls.

## Verification performed this session

- `swift test` — 47 tests, 0 failures.
- `./build.sh debug` — app bundle builds and signs.
- `CGWindowListCopyWindowInfo` — two panel windows, exactly `179×32` at the notch and `148×10` at the top center of the
  non-notched display; layer 26 (above the menu bar); no duplicate rebuild at launch.
- Cursor warp + window inspection — peek grew to `360×84`, long hover to `600×320`, pointer exit collapsed back to the
  handle.
- Synthetic click on the notch and on the handle — both expanded the correct screen's panel.
- Right-click on the expanded panel — a context menu appeared; choosing Settings opened the settings window.
- Accessibility API dump — tabs, sliders (with labels and values), checkboxes, module rows, and the panel gear all expose
  their labels. The window is centered on the screen under the pointer.
- Toggling "Show a handle on displays without a notch" — the non-notched window appeared/disappeared live and the JSON
  file updated.
- Enabling/disabling the clock — `enabledModules` updated in JSON via the accessibility action.
- Copy Diagnostics — the clipboard contained version, macOS, screens/notches, settings JSON, and recent log.
- Collapsed notched window — `CGWindowList` reports alpha 0, so nothing can be drawn around the bezel.
- Offscreen `ImageRenderer` snapshots of the peek/expanded/collapsed panel — confirmed the panel is near-black, the collapsed view is fully transparent, and the module card/layout are aligned.
- `ps` — 0.0% CPU; ~22 MB RSS in debug and ~50 MB in release while collapsed (M1).

### M2 verification (2026-10-25)

- `swift test` — 100 tests, 0 failures.
- `./scripts/build-media-adapter.sh` — adapter v0.7.7 built from the pinned SHA; `/usr/bin/perl … test` exits 0 on
  macOS 26.6.2. `./build.sh debug` and `./build.sh` bundle and sign it; the helper ran from inside `Brim.app`.
- Helper lifecycle — with media enabled, opening the panel started a supervisor (`/bin/sh`) plus Perl; closing it
  removed both after the grace period. `kill -9` on Brim removed both within ~1 s.
- End-to-end stub — the app was launched with `BRIM_MEDIA_ADAPTER_PATH` pointing at a temporary adapter that streamed
  fake metadata/artwork. The AX tree showed “Stub Song”, “Stub Artist”, “Stub Album”, the slider at 37.3 s, 0:37 /
  -2:23, Previous, Pause, Next and the “Player to follow” menu. AXPress on Next/Pause produced `send 4` and `send 2`
  in the stub's log. The stub was removed afterwards; no repository files were changed for it.
- Offscreen `ImageRenderer` — wide (564 pt), half-panel (275 pt), compact (312×30) and empty media cards were
  inspected; the half-panel card drops the album and collapses the source menu so the title still fits.
  Native Menu/Slider are not renderable offscreen (yellow placeholder), which is why the running accessibility tree
  was also checked.
- Idle — collapsed after media use: 0.0% CPU; ~72 MB RSS in the debug build; in the release build ~71 MB right
  after the panel closed and ~33 MB after 25 s, still 0.0% CPU. No helper process remained.
- No permission prompt at launch; `log show` only records the module's Automation request when the module is enabled.

### M3 F7 verification (2026-10-25)

- `swift test` — 157 tests, 0 failures. New suites: agent event validation, roster ordering/retention, a real Unix-socket
  listener (multiple lines, EOF without newline, malformed and oversized input, restart), URL parsing, module lifecycle,
  schema 3 migration and AppModel retention/clear.
- `BRIM_SKIP_MEDIA_ADAPTER=1 ./build.sh debug` — app bundle builds and signs with the `brim` URL scheme in its
  `Info.plist`.
- Running app with the module enabled: the socket existed at
  `~/Library/Application Support/Brim/agent.sock` with mode `0600`; a Python Unix-socket client posted `working` and
  `waiting` events and `log stream` showed both.
- `open -g 'brim://agent?...'` delivered events to the running app, including after the app was already open. The URL
  event appeared in the panel.
- Hover + click on the 179×32 notch opened the panel; the accessibility tree showed `AGENTS`, `Needs input`, the session
  title/detail/cost/elapsed text, and one dismiss button per row. Waiting rows sorted above working and done.
- `brim://agent?action=dismiss...` removed one row; `action=clear` produced the “No agent activity” empty state.
- Quitting Brim removed the socket file. Disabling the module is covered by unit tests and uses the same stop path.
- The user's original schema-2 settings file was restored after the run.

## Decisions log

| Date | Decision | Why |
| --- | --- | --- |
| 2026-10-25 | Resize each panel window to the visible panel rect | Click-through outside the panel without hit-testing hacks; collapsed window is exactly the notch |
| 2026-10-25 | Pointer tracking with global + local `NSEvent` monitors and an `NSTrackingArea` | Global monitors cover other apps; tracking covers a non-key panel while Brim is inactive |
| 2026-10-25 | `AnyView` for module views | Simplest host for M1; revisit only if idle CPU or update cost shows up |
| 2026-10-25 | Generic permission flow, no real permission in M1 | F4 requires the mechanism; media (M2) will exercise Automation |
| 2026-10-25 | Clock updates every minute, only while peek/expanded | Keeps collapsed idle cost near zero |
| 2026-10-25 | Pass the emitted `@Published` value into `NotchWindowManager.apply` | `@Published` fires in `willSet`; reading `model.settings` inside the sink rebuilds with the old value |
| 2026-10-25 | Toggles that need an accessibility action must not use `.labelsHidden()` | On macOS it strips `AXPress` from the resulting checkbox |
| 2026-10-25 | Module enable/disable is synchronous when no permission is needed | A toggle must reflect immediately, and accessibility actions re-read the binding right away |
| 2026-10-25 | Set the collapsed notched window's alpha to 0 | Guarantees no stray background pixel, shadow or compositing edge is visible around the bezel |
| 2026-10-25 | Sequence content: peek first, expanded after the window is nearly grown | Switching layouts while the window resized made the content reflow and look clunky |
| 2026-10-25 | Give each layout a fixed target size inside the window | The content no longer stretches/reflows during the frame animation; only opacity/offset changes |
| 2026-10-25 | Keep the chrome at its previous visual state while collapsing | The panel visibly retracts into the notch instead of blinking off before the window moves |
| 2026-10-25 | Bundle `ungive/mediaremote-adapter` v0.7.7, built from source by a pinned script | MediaRemote is closed to third-party apps on 15.4+; Perl is still trusted. User approved the BSD-3 helper over reimplementing private APIs |
| 2026-10-25 | Run the helper only while a panel is open | The stream costs ~25 MB RSS; kept the collapsed idle budget under 80 MB |
| 2026-10-25 | Wrap the stream in a one-second `/bin/sh` supervisor | Killing/crashing Brim otherwise orphaned the Perl stream forever |
| 2026-10-25 | Stream with `--debounce=150` and apply the adapter's diff protocol | Full artwork only on track changes; one-second updates carry a few fields |
| 2026-10-25 | Hash artwork and cache `NSImage` by that hash | Avoid comparing/decoding hundreds of KB on every progress tick |
| 2026-10-25 | Follow = Automatic, or Spotify/Music via Apple Events | The adapter exposes only the system's single Now Playing; choosing between two players needs direct access |
| 2026-10-25 | Media module off by default; settings schema 2 | Keep M1's panel unchanged until the user opts in and sees the permission explanation |
| 2026-10-25 | Panel active from the first peek until the collapse animation ends, plus a 1 s stop grace | Artwork must not vanish while the panel retracts; twitchy hover must not restart Perl |
| 2026-10-25 | Split the panel evenly and adapt the media card below 320 pt | The clock needs its width for the 54 pt time; the media card hides the album/menu text instead of squeezing the clock |
| 2026-10-25 | Do not close the helper's pipe while its readability handler may be reading | FileHandle raised `NSFileHandleOperationException` on close; terminating the helper produces EOF safely |
| 2026-10-25 | Center one media group (artwork + metadata, progress, transport) in the card | The old Spacer left a large dead area and put the transport under the text column |
| 2026-10-25 | Show “Playing in <app>” in the card and append the app to the peek subtitle | macOS only exposes the host app; the source was hidden when the half-width card collapsed the menu label |
| 2026-10-25 | Stack the settings reorder chevrons in 20×14 frames | Side-by-side 9×5 borderless buttons were hard to hit and looked misaligned |
| 2026-10-25 | Agent ingestion via a Unix socket plus `brim://agent`, not a localhost HTTP port | No TCP listener to authenticate or firewall; a URL is the simplest one-line hook, a socket handles frequent events |
| 2026-10-25 | Keep agent aggregation in `State/AgentRoster` and prune only on events/panel open | Waiting/working state must not cost a timer while the notch is collapsed |
| 2026-10-25 | Socket directory `0700`, socket `0600`, `getpeereid` same-user check | Agent events can include prompts and paths; another local user must not read or inject them |
| 2026-10-25 | Never auto-expire working/waiting sessions | A long tool run that emits no event for a while is not a failure; the user can dismiss it |
| 2026-10-25 | Agent Status is off by default, needs no permission and has no network code | Keeps the M1/M2 panel unchanged and preserves the no-prompt-at-launch rule |
| 2026-10-25 | Schema 3 adds a 10-minute finished-session retention | The panel should clear old completions without user housekeeping, but failures stay visible long enough to notice |

## Session log

### 2026-10-25 — planning

- Read the spec and the sibling Speakeasy project; mapped its structure to Brim.
- Wrote this progress file, the M1 file list and the protocol draft. No code.
- M1 plan approved by the user.

### 2026-10-25 — M1 implementation

- Scaffolded `Package.swift`, `build.sh`, `Info.plist`, app entry point.
- Implemented `ScreenInfo`/notch geometry, settings store + schema 1, login item, permissions placeholder, logging,
  diagnostics.
- Implemented the pure `PanelGeometry`/`PanelStateMachine` with a fake-clock test suite.
- Implemented `NotchWindow`, per-screen controller/manager, pointer monitor, inactive-app tracking area, and animated
  frame changes.
- Implemented `BrimModule`, registry, clock module, panel chrome, settings window, module ordering and permission sheet.
- Implemented right-click Settings/Quit, hidden main menu, launch at login, Copy Diagnostics.
- Found and fixed three runtime issues:
  - launch-time screen notifications rebuilt the panels repeatedly → compare a screen signature;
  - a tracking-area exit fired while the window grew under a still pointer → forward the real pointer and ignore
    spurious exits;
  - `@Published` fires before the stored value, so the non-notched toggle rebuilt with the old value → pass the emitted
    settings into the rebuild.
- Found and fixed two accessibility issues: unlabeled settings toggles, and `.labelsHidden()` stripping the module
  checkbox's `AXPress`.
- Verified the window layout, hover/expand/collapse, context menu, settings, persistence and diagnostics against the
  running app (details above). Visual checks and full-screen/hot-plug checks remain for a human.
- Committed as `7e0b495` (`Milestone 1: notch panel shell (F1–F5)`).

### 2026-10-25 — M2 implementation

- Read the spec and M1 handoff; spiked the MediaRemote adapter in a temp directory before proposing M2.
- Built `ungive/mediaremote-adapter` v0.7.7 from source; `test` exits 0 on macOS 26.6.2, `get` returns null when
  nothing is playing, `stream` idles at 0.0% CPU / ~25 MB.
- Proposed and got approval for the adapter dependency and for shipping media off by default. Implemented F6 in
  `98c4f42` (bundle helper + stream decoder), `d540c80` (coordinator + Apple Events) and `2146164` (media module,
  views, settings schema 2, player choice, panel lifecycle, tests).
- Added the Media module, compact/expanded views, artwork cache, progress/seek, source menu, Settings schema 2 and the
  Media section, panel-lifecycle reporting across screens, Automation status, and diagnostics.
- Found and fixed a real orphan: SIGKILLing Brim left the Perl stream running. Added a shell supervisor that watches
  Brim's PID and kills the helper within a second.
- Found and fixed a FileHandle crash when stopping the stream: closing the read end under a readability handler raised
  `NSFileHandleOperationException`; the service now terminates the helper and lets the handler see EOF.
- Verified the end-to-end path with a temporary stub adapter and the accessibility tree: metadata, artwork, slider,
  time labels, transport buttons, source menu, and `send` commands. No real track was played in this environment.
- Real-player, two-player, Automation-prompt, and visual sign-off remain for a human; see `TESTING.md`.

### 2026-10-25 — M2 UI polish after first use

- User feedback after trying media: the expanded panel felt empty, the transport was centered on the text column
  instead of the card, it was unclear which app was playing, and the settings reorder chevrons were tiny/misaligned.
- Media card: artwork/metadata, progress and transport now form one vertically centered group. The progress bar spans
  the card, the transport is centered on the card, and the metadata includes “Playing in <app>”. The compact peek
  subtitle appends the app name too. Half-panel cards keep the album hidden and the source menu icon-only.
- Clock card: the clock group is vertically centered, so it no longer looks half empty beside the media card.
- Settings: the reorder chevrons are a 20×14 vertical pair instead of 9×5 side-by-side buttons.
- Verified with offscreen renders of the full panel (both modules and media only) and the peek, plus AX frames of the
  settings rows (each chevron 20×14, same x, 15 pt apart, centered on the row).

### 2026-10-25 — visual polish after first look

- User feedback: the notch still showed a shade, the black could be darker, and peek → expanded was clunky.
- Set the collapsed notched window alpha to 0 and confirmed `kCGWindowAlpha=0` against the running app.
- Darkened the panel fill from a grey gradient to black → `0.022` white, and lowered the border/module-card contrast.
- Split the visual state from the layout state. The peek stays planted while the window grows, then the expanded
  layout fades in with a 6 pt lift after the frame is nearly at full size. Each layout has a fixed target size so the
  growing window does not reflow its text.
- Kept the chrome at its previous shape during collapse so the panel retracts into the notch instead of disappearing
  before the window finishes moving.
- Added an offscreen `ImageRenderer` harness (temporary, not committed) to inspect the black level and layout without
  Screen Recording permission.
- Remaining for the user: a look at the real hover → peek → expanded → collapse sequence on the notched MacBook.

### 2026-10-25 — M3 F7 agent status

- Brainstormed M3 with the user and got approval for the first slice: local agent status over a Unix socket + `brim://`
  URL, Claude Code as the reference integration, no network and no permissions.
- Implemented `AgentEvent`/`AgentSession`, the pure `AgentRoster` (urgency order, stale-event guard, retention, 8-session
  cap), the POSIX `AgentSocketService` (line framing, 8 KB limit, `0600` socket, same-user check), the pure
  `AgentURLRouter`, and `AgentModule`.
- Added the peek and card views, the Agents settings section (socket path/copy, retention, clear finished), schema 3,
  diagnostics, the URL scheme and quit cleanup.
- Found and fixed a test-only main-actor deadlock: an 8 KB write from the test blocked the same actor that had to drain
  the socket. Test writes now run off the main actor.
- Found the system temp directory is longer than the ~104-byte Unix-socket limit; socket tests use `/tmp` with a short
  UUID prefix.
- Verified against the running app: socket mode, socket and URL events, AX tree rows/order/cost/elapsed, dismiss/clear,
  and socket removal on quit. Restored the user's settings afterwards.
- 157 tests pass. Remaining: manual visual/VoiceOver sign-off and a real Claude Code hook run; F8+ are not designed.
- Committed as `F7 agent status; local socket and brim:// ingestion` on 2026-10-25.
