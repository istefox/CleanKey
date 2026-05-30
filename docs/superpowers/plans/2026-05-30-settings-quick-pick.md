# Plan — Settings Panel and Quick-Pick Lock Menu (TDD)

- **Date:** 2026-05-30
- **Mode:** brownfield
- **SPEC:** /Users/stefanoferri/Developer/Apple/CleanKey/SPEC.md §"Feature: Settings and Quick-Pick Lock"
- **ADR:** /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-002-settings-quick-pick.md
- **ARCH:** /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md
- **Stack:** Swift 6, macOS 14 Sonoma+, SwiftUI + AppKit, CGEventTap.
- **Test command:** `xcodebuild test -scheme CleanKey -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`

## Conventions for the implementer

- Conventional Commits in English. Feature branch `feat/settings-quick-pick`, never commit to `main`.
- HITL gate before: `git commit`, `git push`, permanent deletions, schema/entitlement changes.
- TDD: write the failing test first, then minimal implementation, then refactor.
  UI-bound and tap-bound code is verified by integration/manual tests, not unit tests.
- Run the **full test suite** after every task that touches a public contract or deletes a file.
- Any helper script must be Bash 3.2-clean.
- Do not modify `docs/manifests/*.manifest.yml` or `.remember/**`.

---

## Task 1 — Extend LockSettings with 4 new fields; update clamping constant

**Goal:** `LockSettings` persists `overlayMode`, `trackpadMode`, `hudCorner`
alongside `lastDuration`. `minimumDuration` changes from 30 to 5.

Files to create:
- None.

Files to modify:
- `CleanKey/LockSettings.swift` — add enum types `OverlayMode`, `TrackpadMode`,
  `HUDCorner` (all `String` `RawRepresentable`, placed at top of file or in a
  sibling `LockSettingsTypes.swift`); add three computed properties with
  UserDefaults get/set using `String` raw values and fallback defaults; change
  `minimumDuration` from 30 to 5.

Tests to write first (`CleanKeyTests/LockSettingsTests.swift` — extend existing
suite):
- Default values: no stored key → `overlayMode == .blackScreen`,
  `trackpadMode == .locked`, `hudCorner == .bottomRight`.
- Round-trip: save `.hud` / `.free` / `.topLeft`, reload, confirm round-trip.
- Unknown stored value: inject a raw string `"invalid"` directly via `UserDefaults`
  → read back yields the default (not a crash).

Tests to update in the same task:
- `LockSettingsTests.testClampBelowMinimum`: assert clamped value is 5 (was 30).
- `CleanKeyTests/CleanKeyTests.swift:testLockSettingsDefaultDuration`: no change
  needed (default is still 120).

Contract change note: `LockSettings.minimumDuration` changes from 30 to 5.
Grep confirmed one additional call-site in
`CleanKey/Views/TimerPickerView.swift:49` (slider lower bound). That file is
retired in Task 3, so no separate fix is required there. The only test asserting
the old value is `LockSettingsTests.testClampBelowMinimum` — update it here.

Run **full test suite** after this task.

---

## Task 2 — TwoZoneSlider mapping utility (pure logic)

**Goal:** a `TwoZoneSlider` struct with two pure functions:
`durationForPosition(_ position: Double) -> TimeInterval` (position in 0...1,
snapped to nearest 1/20) and `positionForDuration(_ duration: TimeInterval) ->
Double`. No UI imports.

Files to create:
- `CleanKey/TwoZoneSlider.swift` — `struct TwoZoneSlider` with the mapping
  functions and a static `steps: [TimeInterval]` array (21 values).

Tests to write first (`CleanKeyTests/TwoZoneSliderTests.swift` — new file):
- Position 0.0 → 5 s; position 1.0 → 600 s.
- Position 11/20 → 60 s (last short step); position 12/20 → 120 s (first long
  step).
- Round-trip: `positionForDuration(durationForPosition(p))` equals `p` for all
  21 step positions.
- Clamp: position slightly below 0 → step 0; position slightly above 1 → step 20.
- All 21 known durations map to the correct step index.

---

## Task 3 — Retire TimerPickerView; update MenuBarController for quick-pick NSMenu

**Goal:** replace the NSPopover left-click with a quick-pick `NSMenu`. Delete
`TimerPickerView` and its tests.

Observable-contract change: `TimerPickerView`, `TimerPickerViewModel` are
deleted. Call-sites confirmed by grep:
- `CleanKey/Views/TimerPickerView.swift` — file deleted.
- `CleanKey/MenuBarController.swift:68-76` (`setupPopover`) — deleted.
- `CleanKey/MenuBarController.swift:87` (`togglePopover`) — left-click path
  replaced.
- `CleanKey/MenuBarController.swift:102-108` (`togglePopover` method) — deleted.
- `CleanKeyTests/TimerPickerViewModelTests.swift` — file deleted (5 tests;
  superseded by `QuickPickMenuTests` below).

HITL gate: confirm deletion of `TimerPickerViewModelTests.swift` and
`TimerPickerView.swift` before executing.

Files to create:
- None.

Files to delete:
- `CleanKey/Views/TimerPickerView.swift`
- `CleanKeyTests/TimerPickerViewModelTests.swift`

Files to modify:
- `CleanKey/MenuBarController.swift`:
  - Remove `popover` ivar and `setupPopover()`.
  - Replace `togglePopover()` and left-click path with `showQuickPickMenu()`.
  - `showQuickPickMenu()` builds an `NSMenu` with items 15 s, 30 s, 1 min,
    2 min (fixed); adds a 5th item `"<label> (default)"` only when
    `settings.lastDuration` is not in `{15, 30, 60, 120}`.
  - Each menu item action calls `startLock(duration:)` immediately.
  - Replace right-click `showContextMenu()` with a menu containing
    `Settings…` (calls `settingsWindowController.showOrFocus()`) and `Quit`.
  - `MenuBarController` gains a weak or unowned reference to
    `SettingsWindowController` (injected or passed at init — match pattern
    used by `LockManager`).
- `CleanKey.xcodeproj/project.pbxproj` — remove deleted files, add
  `TwoZoneSlider.swift` (from Task 2).

Tests to write first (`CleanKeyTests/QuickPickMenuTests.swift` — new file):
- Unit-test a `QuickPickMenuViewModel` (or free function) that returns the menu
  item list given `lastDuration`. Test: 120 s → no 5th item (matches "2 min");
  150 s → 5th item "2 min 30 s (default)"; 15 s → no 5th item; 5 s → 5th item.

Run **full test suite** after this task to confirm no residual references to
the deleted types.

---

## Task 4 — SettingsWindowController + SettingsView (General tab)

**Goal:** a single-instance `NSWindow` hosting a SwiftUI `SettingsView` with
General tab (two-zone slider, trackpad toggle). No Display tab yet.

Files to create:
- `CleanKey/SettingsWindowController.swift` — `@MainActor final class
  SettingsWindowController`; owns the `NSWindow`; `showOrFocus()` method;
  creates a `NSHostingController<SettingsView>` as `contentViewController`.
- `CleanKey/Views/SettingsView.swift` — `NavigationSplitView` with a sidebar
  listing General (and Display, disabled/empty for now); `GeneralSettingsView`
  embedded; draft state in `@Observable SettingsViewModel`.
- `CleanKey/Views/GeneralSettingsView.swift` — two-zone slider (uses
  `TwoZoneSlider` from Task 2); trackpad segmented control (Locked/Free).

Files to modify:
- `CleanKey/AppDelegate.swift` — add `private var settingsWindowController:
  SettingsWindowController?` strong ref; instantiate after `menuBarController`.
- `CleanKey/MenuBarController.swift` — accept `SettingsWindowController`
  injection (already planned in Task 3 stub).
- `CleanKey.xcodeproj/project.pbxproj` — add new files.

Tests to write first (`CleanKeyTests/SettingsViewModelTests.swift` — new file):
- `SettingsViewModel` initialised from `LockSettings` reflects current values.
- `save()` writes all four fields to the injected `LockSettings`.
- `cancel()` leaves `LockSettings` unchanged (draft discarded).
- `save()` after slider drag updates `lastDuration` to the mapped duration.

No UI rendering tests (integration only). Integration/manual check:
- Right-click → Settings… opens the window; re-clicking focuses, not duplicates.
- Cancel leaves values unchanged; Save persists and closes.

---

## Task 5 — Display tab (overlay mode selector + HUD corner picker)

**Goal:** the Display tab in the Settings window.

Files to create:
- `CleanKey/Views/DisplaySettingsView.swift` — `OverlayMode` segmented control;
  `HUDCorner` 2×2 corner picker (disabled when `overlayMode == .blackScreen`).

Files to modify:
- `CleanKey/Views/SettingsView.swift` — add Display item to sidebar; show
  `DisplaySettingsView` when selected.

Tests: extend `SettingsViewModelTests`:
- When `overlayMode == .blackScreen`, `hudCorner` field is editable in the
  model (UI disables the control; the model does not gate it).
- `save()` persists `overlayMode` and `hudCorner`.

Integration/manual check: corner picker is greyed out when Black Screen is
selected; enabled when HUD Only is selected.

---

## Task 6 — Trackpad-free mode: update EventTapControlling.install() signature

**Goal:** `install(trackpadFree: Bool)` in the protocol and implementation.
The CGEventTap callback passes through pointing-device events when
`trackpadFree == true`.

Observable-contract change: `EventTapControlling.install()` → `install(trackpadFree:)`.

Call-sites confirmed by grep:
- `CleanKey/LockManagerProtocols.swift` — protocol declaration.
- `CleanKey/RealEventTapController.swift:78` — `install()` implementation;
  `TapContext` gains `trackpadFree: Bool`; callback pass-through logic added.
- `CleanKey/LockManager.swift:68` — `tapController.install()` → must pass
  `trackpadMode` value. `LockManager.init` gains a
  `trackpadMode: @escaping @Sendable () -> TrackpadMode` closure parameter
  (default `{ .locked }` to preserve existing test construction).
- `CleanKeyTests/TestHelpers.swift` — `FakeEventTapController.install()`
  must accept `trackpadFree: Bool`; record the value for assertion.
- `CleanKeyTests/LockManagerStateTests.swift` — `sut.startLock(duration:)`
  calls compile unchanged (indirect; the fake absorbs the new parameter).
- `CleanKeyTests/WatchdogTests.swift` — same.

Files to modify:
- `CleanKey/LockManagerProtocols.swift`
- `CleanKey/RealEventTapController.swift`
- `CleanKey/LockManager.swift`
- `CleanKey/MenuBarController.swift` — pass `{ settings.trackpadMode }` closure
  when constructing `LockManager`.
- `CleanKeyTests/TestHelpers.swift`

Tests to write first (`CleanKeyTests/TrackpadModeTests.swift` — new file):
- `LockManager` constructed with `trackpadMode: { .free }` calls
  `fakeController.install(trackpadFree: true)`.
- `LockManager` constructed with `trackpadMode: { .locked }` calls
  `install(trackpadFree: false)`.

Run **full test suite** after this task (contract change, all suites affected).

---

## Task 7 — HUD overlay mode in LockOverlayController

**Goal:** `LockOverlayController` builds compact HUD panels instead of
full-screen windows when `overlayMode == .hud`. Cursor hidden/shown
conditionally on `trackpadMode`.

Protocol change: add `configure(settings: LockSettings)` to `LockPresenting`
with a default no-op implementation.

Files to modify:
- `CleanKey/LockManagerProtocols.swift` — add `configure(settings:)` with
  default no-op.
- `CleanKey/LockOverlayController.swift`:
  - Store `overlayMode`, `trackpadMode`, `hudCorner` from `configure(settings:)`.
  - `present()` checks `overlayMode` and calls `buildFullScreenWindows()` or
    `buildHUDPanels()`.
  - `buildHUDPanels()` creates one `NSPanel` per `NSScreen` (~200×80 pt,
    level `.statusBar`, positioned at the configured corner with 20 pt inset,
    `ignoresMouseEvents = true`, not key/main).
  - `present()` skips cursor-hide calls when `trackpadMode == .free`.
  - `dismiss()` shows cursor only when it was hidden (tracked via a flag).
  - `screensChanged()` rebuilds whatever is currently active (full-screen or HUD).
- `CleanKey/MenuBarController.swift` — call
  `lockManager.presenter.configure(settings: settings)` (via the proxy)
  before `startLock`. The `PresenterProxy` must forward `configure(settings:)`
  to the real presenter.

Tests: integration/manual only for window rendering.
Unit-testable: extract `hudPanelFrame(for screen: NSRect, corner: HUDCorner,
inset: CGFloat) -> NSRect` as a pure function in a new
`CleanKey/HUDLayout.swift` file and test it in
`CleanKeyTests/HUDLayoutTests.swift`:
- `topLeft`: frame origin at (inset, screenMaxY - height - inset).
- `bottomRight`: frame origin at (screenMaxX - width - inset, inset).
- All four corners, including non-zero screen origins (external display offset).

---

## Task 8 — End-to-end integration pass

**Goal:** verify all SPEC success criteria for this feature on hardware.

Manual checklist:
1. Left-click → quick-pick menu appears in ≤ 100 ms with correct labels.
2. 120 s default: no fifth item (2 min is a fixed preset); change default to
   150 s → "2 min 30 s (default)" appears.
3. Selecting a preset starts the lock within 200 ms.
4. Right-click → Settings… opens the window; re-clicking focuses without
   duplicate.
5. Save persists all four fields; Cancel discards.
6. In HUD mode: compact window on every display, positioned at configured corner.
7. In Trackpad Free mode: cursor moves, clicks register, keyboard is blocked,
   triple-Escape still unlocks.
8. Display hotplug while locked with HUD → panels rebuild.
9. All v1 success criteria continue to pass (triple-Escape ≤ 200 ms, overlay
   accuracy, memory ≤ 10 MB locked, codesign + spctl pass).

Run **full test suite** before and after this task.

HITL: stop before `git push` and before tagging the release.

---

## Risks & HITL gates

- **HITL required:** file deletions (`TimerPickerView.swift`,
  `TimerPickerViewModelTests.swift`) before they are executed; `git commit`;
  `git push`; GitHub Release publish.
- **Risk — install() signature change:** the existing five test files that
  construct `LockManager` with a fake tap controller will fail to compile until
  `FakeEventTapController` is updated in Task 6. Run the suite to confirm
  before pushing.
- **Risk — minimumDuration constant change (5 s):** any hardcoded `30` in tests
  or views not caught by grep will silently pass a wrong bound. Search for
  literal `30` in `CleanKeyTests/` before closing Task 1.
- **Risk — HUD window level:** `.statusBar` level may be occluded by other
  status-bar items on multi-display setups. Manual verification on external
  display required in Task 8.
- **Risk — cursor hide/show balance:** `CGDisplayHideCursor` / `NSCursor.hide()`
  are reference-counted. If `configure(settings:)` is called multiple times
  before `dismiss()`, the balance can break. Assert in Task 7 that `present()`
  is only called once per lock and that the cursor-hide flag is reset on
  `dismiss()`.
- **Risk — screensChanged while in HUD mode:** the existing `screensChanged()`
  calls `dismiss()` then `present()`. If `configure(settings:)` has not been
  called before the rebuild, `present()` will fall back to the default (full-
  screen). Ensure `configure(settings:)` is called at lock start and that its
  result is retained across rebuilds.
- **Dependency:** `SettingsWindowController` must be allocated before
  `MenuBarController` references it. Verify construction order in
  `AppDelegate.applicationDidFinishLaunching`.
