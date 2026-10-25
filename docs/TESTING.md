# Manual testing and known limitations

Run on a notched MacBook, with and without an external display, in light and dark mode, and over a full-screen app.
The M1 code was also exercised programmatically (window bounds, accessibility tree, synthetic clicks); the visual
checks below still need a person at the screen. See [`PROGRESS.md`](PROGRESS.md) for what was already verified.

## M1 manual verification — notch panel shell

| Feature | Check | Expected |
| --- | --- | --- |
| F1 | Launch Brim with the lid open and no other app full screen. Look at the notch. | No visible window, glow or shadow at the notch. Nothing steals focus from the front app. |
| F1 | Open a full-screen app (for example Safari or a video). Move the pointer to the notch. | The panel appears over the full-screen app; no Space switch, no Dock icon. |
| F1 | Switch between Spaces (⌃←/⌃→) while the panel is collapsed. | A panel exists on every Space, still aligned to the notch. |
| F1 | Expand the panel, then click an app visible just below and beside the panel. | The click reaches the app; only the panel's visible rectangle takes clicks. |
| F2 | Hover the notch and stop moving. | A short black peek appears within ~150 ms (Settings → General → Peek delay). |
| F2 | Keep hovering after the peek. | The full panel grows downward with a spring; no flicker. |
| F2 | Click the notch once. | The full panel opens immediately. |
| F2 | Expand, then move away. Come back within the collapse delay. | The panel stays open. Leave again and wait ~400 ms: it collapses. |
| F2 | Move the pointer just below the panel edge. | The panel does not flicker; the exit area is a little larger than the panel. |
| F3 | Connect a second display. | One panel per eligible screen; nothing duplicated or left behind. |
| F3 | Disconnect the second display while a panel is open. | Its window disappears; the remaining panel is still aligned. |
| F3 | On a display without a notch, hover the slim handle at the top center. | Peek then expand exactly as on the notched display. |
| F3 | Settings → General → uncheck "Show a handle on displays without a notch". | The handle disappears immediately; the notched display is unaffected. Re-check it: the handle returns. |
| F4 | Expand the panel. | The clock card is visible in the expanded layout; the peek shows the compact clock. |
| F4 | Settings → Modules: turn the clock off, then on. | The panel updates immediately. With nothing enabled, the expanded panel says "No modules enabled" and links to settings. |
| F4 | Add a second module (M2 media) and use the up/down arrows. | The panel order follows the list and survives relaunch. (With only the clock in M1, both arrows are disabled; ordering is covered by unit tests.) |
| F4 | Turn on a module that needs a permission (M2). | No prompt at launch. Turning it on shows Brim's explanation sheet first, then macOS asks. Declining still enables it in a limited form. |
| F5 | Right-click the expanded panel. | A menu with Settings… and Quit Brim appears. Both work. |
| F5 | Settings → General: change both sliders and the handle toggle; quit and relaunch. | Values are restored from `~/Library/Application Support/Brim/settings.json`. |
| F5 | Settings → General → Launch at login. | It appears in System Settings → General → Login Items. The toggle reflects changes made there. Toggle it back off after testing a dev build. |
| F5 | Settings → About → Copy Diagnostics. | The clipboard contains version, macOS, displays/notches, the settings JSON and recent Brim log lines. |
| F5 | Use only the keyboard in Settings. | Tab reaches every control; Space toggles checkboxes; the window is readable and closable with ⌘W. |
| WCAG | Use VoiceOver on the panel and settings. | The gear is "Open Brim settings"; the handle is "Brim panel"; sliders and module toggles have labels; the panel exposes its module content. |
| Perf | Leave Brim collapsed for a minute, then check Activity Monitor. | Under 0.5% CPU and under 80 MB memory. No periodic polling visible in `log stream`. |
| Logs | `log stream --predicate 'subsystem == "com.harshshelar.brim"'` while hovering and opening settings. | Window/state/general messages appear; no `print` output. |

## Notched vs non-notched geometry

- Notched screen: the collapsed window must equal the hardware notch (recorded 179×32 on the development machine).
  Hovering anywhere in that rectangle should peek; clicks in it should expand without activating Brim.
- Non-notched screen: the collapsed window is a 148×10 handle at the top center. It is intentionally interactive, so it
  can receive the click that opens the panel; everything outside its 148×10 rectangle passes through.
- Expanded panel: 600×320, clamped to the screen's width and centered on the screen (not on the notch width).

## Known limitations and notes for M1

- No screenshot-based visual test was possible in the agent environment (Screen Recording permission is not granted to
  the agent process). Use the manual table above for the final look-and-feel sign-off.
- The right-click menu is attached to the visible panel. Right-clicking the collapsed notch itself is left to the menu
  bar/underlying app; the panel is opened by hover/click, and its menu is available once it is visible.
- The collapsed notched window ignores mouse events on purpose. A click there is observed by the global pointer monitor
  and opens the panel, but it also reaches whatever is underneath the notch (normally nothing).
- M1 has no module that needs a permission. `SystemPermissionService` is a placeholder; the explanation/enable flow is
  covered by unit tests with a fake module and will be wired to real checks in M2.
- Launch at login is implemented through `SMAppService.mainApp`. Ad-hoc-signed dev builds can fail registration or
  become stale after a rebuild; test it once, then turn it off. Grant/registration behavior can differ from a
  properly signed release build.
- Settings are written on every change. Dragging a slider writes several times; this is intentional until a debounce is
  needed.
- The clock updates once a minute while the panel is visible; the collapsed panel has no timeline at all.
- Full-screen behaviour and window levels can change between macOS releases. If the panel stops appearing over a
  full-screen app, check `NotchWindow`'s level and collection behaviour first.
- The app is an agent (`LSUIElement`); it has no Dock icon and no menu bar icon. Settings is reachable from the panel
  context menu, the panel gear, or ⌘, while a Brim window is focused.
