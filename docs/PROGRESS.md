# Brim — build progress

This file is the handoff between sessions. Read it with `AGENTS.md` and the spec before touching code, and update it
before ending a session.

**Last updated:** 2026-10-26
**Current milestone:** M1–M3 F8 and the UX revision F9–F14 are complete and signed off by the user (2026-10-26). F14
(hide over full-screen apps, menu-bar-height pill) came out of that sign-off.
**Next action:** F15–F18 are committed and verified by the agent (F18 end to end waits for F20). F19 (Quick
Prompt) is committed with 344 tests passing, but typing into the prompt field has not been confirmed in the real app:
synthetic key events did not reach the field (see the session log). Have the user type a prompt (⌃⌥⌘B, type, Return,
Esc twice), fix what that shows, then build F20. Stretch goals are deliberately not designed.

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
| M1 — Notch panel shell | Complete (F1–F5); signed off 2026-10-26 |
| M2 — Media controls | Complete (F6); signed off 2026-10-26 |
| M3 — AI tools and IDE integration | F7 (agent status) and F8 (alerts/open project) complete; signed off 2026-10-26. Quick prompt and send-to-assistant are not designed |
| UX revision — live notch | F9–F13 complete and signed off 2026-10-26. F14 complete and verified against the running app; 253 unit tests pass |
| Stretch goals | Not started |

Test machine: macOS 26.6.2, Apple Silicon. Displays seen during development: primary 1920×1080 (no notch) and built-in
1470×956 with a 179×32 notch. Minimum target remains macOS 14.

## F14 — what exists

Asked for during the 2026-10-26 sign-off: a full-screen video still showed the ears, and the external display's pill
was 24 pt tall under a 30 pt menu bar.

- `FullScreenDetecting` (Protocols) with `WorkspaceFullScreenMonitor` (`Services/FullScreenMonitor.swift`). It reads
  `CGWindowListCopyWindowInfo` on Space changes, app activation/termination and screen changes, then again 0.4 s and
  1.2 s later while the animation settles. Pure rule in `coveredScreenIDs(windows:screens:excludingPID:)`: another
  app's layer-0 window fills the display below the menu bar strip, and no desktop-icon-level window (Finder,
  WindowManager) covers it. Size alone fails on a notched display, where a full-screen window sits at the same rect as
  a zoomed one; `NSApp.currentSystemPresentationOptions` was tried and stays 0 for other apps.
- `NotchWindowManager` hides covered screens' controllers; `NotchWindowController.setHidden` disables the state machine
  (collapsing an open panel) and orders the window out. Agent alerts are untouched.
- `ScreenInfo.menuBarHeight` (frame top minus visible-frame top) sizes the non-notched live pill; `livePillSize.height`
  is the fallback while the menu bar is hidden. Diagnostics print it.
- Tests: `FullScreenMonitorTests` (window lists recorded on the development machine), a pill-height case in
  `PanelGeometryTests`, and `FakeFullScreen` in `Fakes.swift`. 253 tests.

## UX revision (F9–F13) — what exists

Spec section "UX revision: live notch", written from a NotchNook comparison review. The user asked for the spec and
the implementation in the same request (2026-10-25), which was taken as approval of this plan. The file list below was
the plan and is now what exists.

- **F9** — `PanelState` is `.collapsed`/`.expanded`; the state machine opens on hover (or click only, `opensOnHover`),
  with the live ears as part of the hover target. The controller plays a haptic on open and cross-fades under Reduce
  Motion. The compact/peek views are gone.
- **F10** — `BrimModule` publishes `liveActivity` and draws `liveView(.leading/.trailing)`; `LiveActivityResolver` picks
  attention > media > ambient, ties by module order; `AppModel.liveModuleID` drives `NotchWindowManager.setLive`. Media
  is live while playing (3 s grace). Agents are live while waiting/failed (attention, failures acknowledged on panel
  open) or working (ambient). With the setting on, the media helper runs while the module is enabled; the coordinator
  restarts it with a 5 s / 30 s / 5 min backoff and polls a followed player every 3 s while the panel is closed.
- **F11** — events, sessions and notifications carry an optional validated `app`. `AgentOpenTarget` prefers activating
  the app via Launch Services and falls back to Finder. The notch alert hangs from the top of the pointer's screen,
  pauses on hover, opens on a click anywhere, and is dismissed when a panel opens.
- **F12** — new installs enable media + clock; media needs no permission to enable; the panel's player menu sends the
  user to Settings → Media when Automation is missing; reopening Brim and the first launch show Settings (with a
  welcome note). `ClaudeHookInstaller` installs/updates/removes the hook with backups and refuses unparsable files.
  Settings has General/Media/Agents/Modules/About tabs and "Show a Test Session". Schema 5.
- **F13** — the expanded width is 290 pt per module (min 460) and the manager rebuilds on module-count changes; the
  clock scales instead of wrapping; the media card uses its full layout down to 240 pt and an icon-only source menu.
- Brave, Arc, Firefox, Opera and Vivaldi have named Now Playing sources (found while verifying: Brave showed as
  "Browser").

Tests: `LiveActivityResolverTests`, `ClaudeHookInstallerTests` (temp home directory), rewritten
`PanelStateMachineTests`/`PanelGeometryTests`/`AgentAlertGeometryTests`, and new cases in media module, coordinator,
agent module/event/roster/URL, settings and AppModel suites. 247 tests total.

Protocol and model changes:

```
Model/PanelState.swift          .collapsed / .expanded (peek removed)
Model/LiveActivity.swift        NEW  LiveActivity (priority), LiveActivityPriority, LiveActivityEdge
Model/Settings.swift            schema 5: opensOnHover, showLiveActivity; new-install modules media + clock
Model/AgentEvent.swift          optional `app` bundle ID on events, sessions and notifications
Modules/BrimModule.swift        compactView() → liveActivity + liveActivityPublisher + liveView(_:)
Services/Protocols.swift        SettingsPersisting.hasSavedSettings; WorkspaceOpening.activateApplication;
                                AgentNotifying.onOpen(AgentOpenTarget); ClaudeHookInstalling (NEW)
Services/NowPlayingService.swift  NowPlayingProviding.setPanelVisible(_:) (slower poll while closed)
```

Files:

```
State/PanelStateMachine.swift   F9  hover/click open, live hit area, no peek
State/PanelGeometry.swift       F9/F10/F13  live frame, pill, width per module count
State/LiveActivityResolver.swift  F10 NEW  highest priority wins, ties by module order
Window/NotchWindowController.swift  F9/F10  live frame animation, haptic, reduce motion
Window/NotchWindowManager.swift F10/F13  forwards live state, rebuilds on module count
Window/AgentAlertPresenter.swift  F11  top-anchored alert on the pointer's screen, hover pause
State/AgentAlertGeometry.swift  F11  top-anchored frame, screen choice
UI/PanelView.swift              F9/F10  no peek, live ears
UI/MediaLiveView.swift          F10 (replaces MediaCompactView)
UI/AgentLiveView.swift          F10 (replaces AgentCompactView; keeps AgentStatusGlyph)
UI/AgentAlertView.swift         F11  panel shape, whole card clickable
UI/SettingsView.swift           F9/F10/F12  General / Media / Agents / Modules / About tabs, welcome note
Modules/MediaModule.swift       F10/F12  live activity + 3 s grace, background monitoring, no required permission
Modules/AgentModule.swift       F10/F11  live activity, acknowledgement, dismiss alert on open, open app
Services/NowPlayingCoordinator.swift  F10  helper restart backoff, 3 s poll while closed
Services/WorkspaceService.swift F11  activate an app by bundle ID
Services/ClaudeHookInstaller.swift  F12 NEW  hook script + settings.json merge/remove, pure static helpers
App/AppModel.swift              F10/F12  live module, settings tab, first launch, panel player choice
App/BrimApp.swift               F12  reopen opens Settings
```

## M3 F8 — what exists

F8 adds opt-in agent alerts and a project action without introducing network access:

```
Sources/BrimKit/Model/AgentNotification.swift          notification content + authorization status
Sources/BrimKit/State/AgentNotificationTracker.swift    transition rules (waiting/error, no duplicates, panel-aware)
Sources/BrimKit/State/AgentAlertGeometry.swift          pure notch/toast placement
Sources/BrimKit/Services/UserNotificationService.swift  UNUserNotificationCenter wrapper + click routing
Sources/BrimKit/Services/WorkspaceService.swift          opens a project folder in Finder
Sources/BrimKit/Window/AgentAlertPresenter.swift        notch alert window, auto-dismiss, click action
Sources/BrimKit/UI/AgentAlertView.swift                  the notch alert card
```

Changed: `AgentModule` posts a system notification when macOS allows it and falls back to Brim's notch alert
otherwise; `AppModel` owns the opt-in setting/permission state; `Settings` is schema 4 with
`agentNotificationsEnabled`; the Agents settings section has the explanation/toggle/denial note; agent rows have a
folder button; diagnostics include notification state.

The macOS notification path is correct but cannot prompt for this ad-hoc dev build; macOS returns “Notifications are
not allowed for this application.” The notch alert is the guaranteed path in development, and system banners are used
when a signed build has permission. Clicking either kind of alert opens the session's `cwd` in Finder.

Tests: `AgentNotificationTrackerTests`, `AgentAlertGeometryTests`, notification/open-project cases in
`AgentModuleTests`, schema-4 migration and AppModel permission tests. 184 tests total.

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
`AgentURLRouterTests`, `AgentModuleTests`, plus schema-3 and AppModel retention/clear tests. 184 tests total after F8.

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
- [x] Light/dark mode, external display, full-screen app visually checked. (External display behavior verified programmatically; visual appearance still pending.)

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
- [x] **Manual visual sign-off**: light/dark mode, a long session list, and the card beside clock + media on the notched
  display. See [`TESTING.md`](TESTING.md).

## UX revision acceptance checklist

`[x]` = implemented and covered by a unit test or checked against the running app (see the "Verified by the agent"
note in [`TESTING.md`](TESTING.md)). `[ ]` = needs a person at the screen.

- [x] **F9** Hover opens the full panel after the hover delay; no peek. Verified with a pointer warp (934×320).
- [x] **F9** Open mode (hover/click) in settings, schema 5 migration. Unit tested.
- [x] **F9** Haptic tap and Reduce Motion cross-fade. Code paths exist; not observable here.
- [x] **F10** Live ears while media plays (259×32 on the 179×32 notch; 150×24 pill on the external display), from the
  real Brave/YouTube stream with the panel closed.
- [x] **F10** Agent waiting takes the ears from media; working hands them back. Verified with socket events.
- [x] **F10** Grace period, acknowledgement, priority, helper lifecycle and restart backoff. Unit tested.
- [x] **F10** Clicks on the ears never reach the menu bar; idle CPU/memory with the helper running for 10 minutes.
- [x] **F11** `app` validation/transport, open-app-then-Finder fallback, dismiss-on-open. Unit tested.
- [x] **F11** The alert drops from the top of the pointer's screen. Verified (360×64 at y 0 on the external display).
- [x] **F11** Click-anywhere and hover-pause on the real card; a real Claude Code session switching to its terminal.
- [x] **F12** Defaults, no-permission media, panel player choice, first launch, hook install/update/remove. Unit tested.
- [x] **F12** Reopen shows Settings with the five tabs. Verified.
- [x] **F12** Update… on the real `~/.claude/settings.json` (left for the user: it edits their Claude Code config).
- [x] **F13** Width per module count, clock line limit, media full layout threshold. Unit tested; 934 pt seen live.
- [x] Light/dark mode, full-screen app, keyboard-only settings, VoiceOver on the ears and the alert.

## M3 F8 acceptance checklist

- [x] **Opt-in only**: Agent alerts are off by default; enabling them shows an in-app explanation before any macOS
  permission request. Nothing is requested at launch.
- [x] **Transition rules**: a session newly entering `waiting` or `error` alerts once; repeated events in the same state
  do not. A transition back through working can alert again. An open panel suppresses alerts. Unit tested.
- [x] **System path**: with notification authorization, `UNUserNotificationCenter` posts a banner with the session's
  title/body and `cwd`; clicking it opens the project. Unit tested through the module/fake notifier; real banners need a
  signed build on this machine.
- [x] **Notch-alert fallback**: when macOS notifications are unavailable/denied, a 360×72 card appears under the notch,
  carries the same title/body, auto-dismisses after 7 seconds, and does not activate Brim. Verified against the running
  ad-hoc build with the window-list and accessibility tree.
- [x] **Notch-alert action**: the folder button opens the project in Finder; the close button dismisses it. Row folders
  use the same workspace service. Verified for the panel row; the toast uses the same tested path.
- [x] **Settings schema 4**: the notification flag round-trips; schema 3 files migrate without losing values; a denied
  system permission keeps the notch fallback enabled and explains why.
- [x] **Diagnostics** include notification enabled/authorization state.
- [x] **Manual sign-off**: a signed build's macOS banner, its click behavior, and the notch alert in light/dark mode.

## Manual sign-off

Done by the user on 2026-10-26: every item below and every manual row in [`TESTING.md`](TESTING.md). The sign-off
found two issues, both fixed in F14: the ears stayed over a full-screen video, and the external display's pill was
shorter than its menu bar. The list is kept as a record of what was checked.

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
- M3: the documented Claude Code hook with a real Claude Code session (permission prompt → waiting, stop → done). The
  hook and user settings are installed on the development machine and verified with the exact command Claude Code runs
  (synthetic payload); a real session still needs a restart and sign-off.
- M3: keyboard/VoiceOver use of the session dismiss and clear controls.
- M3 F8: a signed build's macOS banner, its click-to-open-project behavior, and the permission prompt.
- M3 F8: the notch alert in light/dark mode, with the pointer and another app active.

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

### M3 F8 verification (2026-10-25)

- `swift test` — 184 tests, 0 failures. New coverage: notification transition rules, notch-alert geometry, module
  fallback/open-project/alert-dismiss behavior, schema-4 migration and AppModel permission behavior.
- `./build.sh debug` — app bundle builds and signs with `UserNotifications` linked.
- Running ad-hoc build with Agent Status on and alerts enabled: sending a `waiting` event while the panel was closed
  produced a `361×72` window at `(2475, 40)` under the 179×32 notch. The accessibility tree read “Claude Code needs your
  input” and the session detail. It disappeared after the 7-second auto-dismiss and Brim kept running.
- Settings showed the toggle on and the note “macOS banners are off; Brim will show a notch alert instead.” The backend
  reports `authorizationStatus = denied` for this ad-hoc bundle; `requestAuthorization` fails with “Notifications are
  not allowed for this application” on macOS 26.6.2. This is a signing limitation, not a Brim logic failure; signed
  builds should get the banner path.
- The row folder button opened Finder at the session's `cwd`. The notch alert uses the same `WorkspaceService` and the
  action is unit tested through `FakeWorkspace`.
- Test sessions were cleared; Brim was left running. The development settings file is now schema 4 with agent alerts on.

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
| 2026-10-25 | Agent alerts use a notch card when macOS notifications are unavailable | Ad-hoc dev builds cannot register for `UNUserNotificationCenter`; the opt-in feature must still work and match Brim's visual language |
| 2026-10-25 | Alerts fire only on a transition into waiting/error, and not while a panel is open | Repeated hooks should not spam banners; the user is already looking when the panel is open |
| 2026-10-25 | Open project uses Finder rather than Terminal | No app-specific terminal detection or Automation permission; Finder always exists and the path is visible |
| 2026-10-25 | Schema 4 adds the opt-in agent alert flag | The alert is off by default and never asks for a permission at launch |
| 2026-10-25 | Replace the hover peek with a live notch (UX revision) | NotchNook-style: glanceable state belongs at rest, not behind a hover; the peek duplicated the panel and added 0.7 s |
| 2026-10-25 | Keep the media helper running while the live notch is on | Brim (~33 MB) plus the helper (~25 MB) stays under the 80 MB budget; without it the notch cannot know what plays |
| 2026-10-25 | One module owns both ears; attention > media > ambient | Splitting ears between modules was unreadable at 40 pt; an agent that needs you matters more than music |
| 2026-10-25 | Ears appearing under a resting pointer never open the panel | Media starting while the pointer sits near the notch must not pop the panel open |
| 2026-10-25 | Opening the panel acknowledges failures, not waits | A failure has been seen once the panel shows it; a wait still needs action in the agent's app |
| 2026-10-25 | Open the session's app via Launch Services, fall back to Finder | `NSRunningApplication.activate` is ignored for an inactive caller on macOS 14+; Finder was the wrong destination for "needs input" |
| 2026-10-25 | Hook reports `$__CFBundleIdentifier` and the project folder name | macOS sets the variable for processes launched from an app, so the hook names Terminal/iTerm/VS Code with no config |
| 2026-10-25 | Brim edits `~/.claude/settings.json` only from an explicit button, with a backup, never when unparsable | It is another app's config; the user must see what changes and be able to undo it |
| 2026-10-25 | Panel width grows by 290 pt per module instead of splitting 600 pt | Three modules at ~178 pt each truncated the media card and wrapped the clock |
| 2026-10-25 | Now Playing needs no permission to enable; new installs enable media + clock | The headline feature was behind an Automation sheet it doesn't need |

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

### 2026-10-25 — F7 Claude Code integration setup

- The user reported no Claude Code activity in the panel. Inspection showed the integration had not been installed:
  `~/.brim/claude-hook.sh` was missing and `~/.claude/settings.json` had no `hooks` block. Brim was also not running at
  one point.
- Installed the hook script, made it executable, merged `SessionStart`, `PreToolUse`, `Notification`, `Stop` and
  `SessionEnd` hooks into `~/.claude/settings.json`, and backed the original up to
  `~/.claude/settings.json.brim-backup-20261025-214113`.
- Verified the exact shell command Claude Code runs with a synthetic `Notification` payload: `log stream` showed the
  event and Brim's accessibility tree showed “Claude Code / Needs input / Manual setup check”. Cleared the test row.
- Claude Code reads hooks at session start; the running `claude` process predates the config, so a restart/new session
  is required. `/hooks` confirms registration and `claude --debug=hooks` shows execution.
- Brim was left running with Agent Status enabled. Real-session sign-off is still pending.

### 2026-10-25 — M3 F8 agent alerts and open project

- Implemented opt-in alerts: notification transition tracker, `UNUserNotificationCenter` wrapper, notch-alert fallback,
  settings schema 4, permission explanation and denial note, diagnostics, and Finder project actions on rows and alerts.
- Found the macOS constraint the hard way: `requestAuthorization` returns “Notifications are not allowed for this
  application” for the ad-hoc `LSUIElement` build, even after copying it to `/Applications` and registering it with
  LaunchServices. A signed build is required for system banners.
- Added the notch-alert window as the guaranteed path: a 360×72 card under the notch, auto-dismissing after 7 seconds,
  non-activating, with open-project and dismiss buttons. Verified it with a live event and the window/accessibility
  lists; Brim stayed running after dismissal.
- Added folder buttons to agent rows and verified Finder opens the session's `cwd`.
- 184 tests pass. Remaining: signed-build banner/click sign-off, notch-alert light/dark/VoiceOver sign-off. Quick prompt and
  send-to-assistant are still not designed.

### 2026-10-25 — UX review and revision (F9–F13)

- Reviewed the implementation against NotchNook and the spec from a user's point of view. Main findings: the collapsed
  notch never showed anything (media helper stopped, no live activity), the peek duplicated the panel, agent alerts led
  to Finder and overlapped an opened panel, setup hid the headline features (clock-only default, an Automation sheet
  to enable media, a hand-installed Claude Code hook, no reopen), and three modules squeezed into 600 pt.
- Wrote the spec section "UX revision: live notch" (F9–F13 plus not-designed items) and the file/protocol plan above.
- Implemented F9–F13 as described in "UX revision — what exists". 247 tests pass.
- Verified against the running debug build: live ears with real media, hover to open/collapse, agent priority over
  media, the alert on the pointer's screen, reopen → Settings, diagnostics, and the hook script against a scratch
  socket. Found and fixed Brave showing as "Browser". Restored the user's settings file afterwards; Brim was left not
  running, as it was found.
- Not committed: the user asked for implementation, not a commit. Not done: the user's own Claude Code hook was left
  at the old version (Settings → Agents → Update… upgrades it).

### 2026-10-26 — manual sign-off and F14

- The user signed off every manual check (M1, M2, F7, F8, F9–F13) and reported two issues: the notch stayed visible
  over a full-screen video, and the live pill looked off. The pill screenshot was the 150×24 pill on the 1080p
  external display, whose menu bar is 30 pt.
- Probed full screen with a scratch app on each display. Findings: on the notched display the full-screen window is
  `1920,33 1470×923`, identical to zoomed windows, and the menu bar window stays listed; the app's title-bar strip
  window is alpha 0; `currentSystemPresentationOptions` stays 0 for other apps. The reliable signal is the missing
  desktop: Finder's and WindowManager's desktop-icon-level windows for that display leave the list.
- Implemented F14 as described in "F14 — what exists" and added it to the spec; ticked every acceptance box in the
  spec and amended F1 ("over full-screen apps") and F10 (pill height).
- Verified with debug and release builds: Brim hid only the full-screen display and came back afterwards on both
  displays; the pill is now `150×30`. 253 tests pass. Brim was left running from `build/Brim.app` (release).

### 2026-10-26 — design round for F15–F20

- Decisions: displays via a mode picker (all / notched only / main only); a recordable global shortcut with no default;
  focus only when opened by keyboard; gestures = scroll to open and swipe the media ears to skip; dragging toward the
  notch opens drop zones; quick prompt runs the local `claude -p` with read-only tools in a chosen folder, as a prompt
  bar over the cards; send to assistant accepts dropped files, clipboard, screenshot and selected text. Build order:
  Panel input (F15–F18), then F19–F20. No stretch goals for now (S1 tray, when designed: references kept until
  removed).
- Checked the installed CLI (Claude Code 2.1.310): `--tools`, `--output-format stream-json`,
  `--include-partial-messages`, `--resume` and `--add-dir` exist.
- Defaults the agent chose while writing criteria, to confirm with the user: clicking the prompt field and dropping
  onto Ask Claude take focus (exceptions to keyboard-only focus); the shortcut shows the panel over a full-screen app;
  "notched only" falls back to the main display with the lid closed; F18 has no visible drop zone until F20; the
  attachment limits (10 items, 20 MB each).

### 2026-10-26 — Panel input (F15–F18) and Quick Prompt (F19)

- The user approved the defaults from the design round by asking to start implementation.
- F15 display mode (schema 6), F16 global shortcut and keyboard focus, F17 scroll/swipe gestures and F18 drag
  detection with module drop zones: one commit each, verified as recorded in `TESTING.md`.
- F19: `QuickPromptModule` (a bar above the cards, takes over the panel while a conversation shows),
  `ClaudeCLIRunner` (`claude -p` with `--tools Read,Grep,Glob --strict-mcp-config`, prompt on stdin,
  `BRIM_QUICK_PROMPT=1`), `ClaudeCLILocator`, `ClaudeStreamParser` (from recorded 2.1.310 output), a small Markdown
  block renderer, settings schema 7 and hook version 3 (skips quick prompt runs). The window now catches Esc before a
  focused text field, and modules can use it first (`handleEscape`).
- Verified: one real `claude -p` run in the stream-json mode; the panel opens at 630×366 with the bar and focus on the
  field (after deferring the focus request until the window is key).
- Not verified: typing into the field. Synthetic CGEvent typing left the field empty; two unexplained Brim-owned
  windows appeared (312×237 at layer 101 under the field, 500×500 at layer 0), and one attempt opened Choose Folder…
  and blocked the main thread until Brim was quit. Screenshots through `screencapture` triggered a macOS "tmux is
  requesting to bypass the private window picker" prompt, so the agent stopped GUI automation.
- The user's settings were left in a test configuration (Quick Prompt on, ⌃⌥⌘B); the original is backed up in the
  session scratchpad.

