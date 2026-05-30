# ADR-002 — Settings Panel and Quick-Pick Lock Menu

## Status

Accepted — 2026-05-30

## Context

CleanKey v1 exposes a single NSPopover with a duration slider. Three usability
problems motivate this ADR:

1. Every lock start requires slider interaction — there is no one-tap path for
   common durations.
2. There is no way to configure overlay mode or trackpad behavior without
   editing source.
3. The existing `LockSettings` struct stores only `lastDuration`; three new
   fields (overlayMode, trackpadMode, hudCorner) must be persisted without
   breaking existing UserDefaults keys.

This is a brownfield extension. ADR-001 established invariants that are
non-negotiable here: `LockManager.startLock(duration:)` and `unlock()` public
signatures are frozen; `LockManager` may not gain UI dependencies; the
`LockPresenting` injection seam and fixed teardown order are preserved.

Six design questions have long-term impact and are decided below.

## Decision

### Decision 1 — LockSettings extension strategy

Add the three new fields as independent UserDefaults keys beside `lastDuration`.
Represent `OverlayMode`, `TrackpadMode`, and `HUDCorner` as `RawRepresentable`
enums with `String` raw values; persist the raw string directly. Missing or
unrecognized keys fall back to the enum's declared default without migration.

The `LockSettings` struct gains three computed properties with the same
get/set pattern as `lastDuration`. The existing `minimumDuration`,
`maximumDuration`, and `defaultDuration` constants change: `minimumDuration`
drops from 30 s to 5 s to match the new SPEC range.

**Existing call-sites affected by the `minimumDuration` constant change:**

- `CleanKey/LockSettings.swift` — `minimumDuration` declaration (30 → 5)
- `CleanKey/Views/TimerPickerView.swift:49` — slider lower bound uses
  `LockSettings.minimumDuration`
- `CleanKeyTests/LockSettingsTests.swift:21-22` — test that clamping < 30
  → 30; must be updated to clamp < 5 → 5
- `CleanKeyTests/CleanKeyTests.swift` — no direct minimumDuration reference,
  no change needed

The full test suite must be run after this constant change; the clamping tests
in `LockSettingsTests` will fail and must be updated.

### Decision 2 — Overlay protocol extension vs new HUDPresenting protocol

Extend the existing `LockPresenting` protocol with a new optional method
`configure(settings: LockSettings)` rather than introducing a separate
`HUDPresenting` protocol.

`LockPresenting` already has a default-impl extension pattern (`tick` has a
no-op default). Adding `configure(settings:)` with a no-op default preserves
all existing conformers (`SilentPresenter`, `PresenterProxy`,
`FakeLockPresenter`) without any changes to their source. `LockOverlayController`
overrides `configure(settings:)` to decide at present-time whether to build
full-screen windows or compact HUD panels, and which corner to use.

This avoids a parallel protocol hierarchy that would require changes in
`LockManager` and all injection sites.

**Call-sites for `LockPresenting` that need review (no signature change, only
new default method — zero breakage):**

- `CleanKey/LockManagerProtocols.swift` — protocol declaration (add method +
  default impl)
- `CleanKey/LockOverlayController.swift` — override `configure(settings:)`,
  split `buildWindows()` into full-screen and HUD paths
- `CleanKey/MenuBarController.swift` — `PresenterProxy` and `SilentPresenter`
  pick up the default impl automatically
- `CleanKeyTests/TestHelpers.swift` — `FakeLockPresenter` picks up default impl
  automatically

### Decision 3 — Left-click (quick-pick) vs right-click (Settings) in NSStatusItem

`MenuBarController.setupStatusItem()` already sets
`sendAction(on: [.leftMouseUp, .rightMouseUp])` and inspects
`NSApp.currentEvent?.type` in `statusItemClicked`. This pattern stays unchanged.

Left-click path: instead of toggling the popover, build and pop up an `NSMenu`
via `NSMenu.popUpContextMenu(_:with:for:)`. The four fixed presets plus the
conditional custom-default item are NSMenuItems with action `startLockPreset(_:)`.

Right-click path: `showContextMenu()` is replaced with a menu containing
`Settings…` and `Quit`. The `Settings…` item calls
`SettingsWindowController.showOrFocus()`.

This feature retires the old `NSPopover` and `TimerPickerView` entirely;
`setupPopover()` is removed and the popover ivar is deleted.

**Call-sites for `TimerPickerView` / popover:**

- `CleanKey/MenuBarController.swift:68-76` — `setupPopover()` (deleted)
- `CleanKey/MenuBarController.swift:102-108` — `togglePopover()` (deleted)
- `CleanKey/Views/TimerPickerView.swift` — file retired; both
  `TimerPickerView` and `TimerPickerViewModel` are removed
- `CleanKeyTests/TimerPickerViewModelTests.swift` — test file must be removed
  or repurposed; 5 test cases reference `TimerPickerViewModel` which will no
  longer exist

Because removing `TimerPickerView` changes an observable contract (a public
type used in tests), an explicit task in the plan covers updating/removing those
tests before the view is deleted.

### Decision 4 — Trackpad-free mode in the CGEventTap callback

`RealEventTapController.install()` now accepts a `trackpadMode: TrackpadMode`
parameter (not stored in `LockSettings` directly at call time — the caller
reads settings and passes the value). Inside `eventTapCallback`, the context
struct (`TapContext`) gains a `trackpadFree: Bool` field.

When `trackpadFree == true`, the callback returns
`Unmanaged.passUnretained(event)` (pass-through) instead of `nil` for
pointing-device event types: `.leftMouseDown`, `.leftMouseUp`,
`.leftMouseDragged`, `.rightMouseDown`, `.rightMouseUp`, `.rightMouseDragged`,
`.otherMouseDown`, `.otherMouseUp`, `.otherMouseDragged`, `.mouseMoved`,
`.scrollWheel`. Gesture events (raw 18, 19, 20, 29, 30, 31, 32) and system
events (raw 14) are also passed through in free mode.

The callback processes keyboard events and `tapDisabledBy*` sentinels
identically regardless of mode. The Escape-combo evaluator path remains unchanged.

The `EventTapControlling` protocol's `install()` signature changes to
`install(trackpadFree: Bool)`. This is a **contract change**:

Call-sites for `EventTapControlling.install()`:
- `CleanKey/LockManager.swift:68` — `tapController.install()` → must pass
  `trackpadFree` read from an injected settings accessor
- `CleanKey/RealEventTapController.swift:78` — `install()` implementation
- `CleanKeyTests/TestHelpers.swift` — `FakeEventTapController.install()`
  (if present — confirm in TestHelpers before coding)
- `CleanKeyTests/LockManagerStateTests.swift` — all calls to
  `sut.startLock(duration:)` exercise `install()` indirectly via the fake;
  the fake must accept the new parameter
- `CleanKeyTests/WatchdogTests.swift` — same indirect path

`LockManager` must gain a `TrackpadMode` accessor (passed through to the tap
controller at lock start). The cleanest seam: `LockManager.init` accepts a
`settings: LockSettings` value (or a closure `trackpadMode: @Sendable () ->
TrackpadMode`) rather than storing the full settings object (which would
re-introduce the old `lastDuration` mutation pattern). Decision: inject a
`@Sendable () -> TrackpadMode` closure so `LockManager` remains UI-free and
`LockSettings`-free.

The full test suite must be run after this contract change.

### Decision 5 — Settings window ownership and single-instance guarantee

A new `SettingsWindowController` owns the `NSWindow` hosting a SwiftUI
`SettingsView` (a `NavigationSplitView` with General and Display tabs).
`AppDelegate` holds a strong reference to `SettingsWindowController` (same
pattern as `MenuBarController`).

`SettingsWindowController.showOrFocus()` is idempotent: if the window is
already visible it calls `window.makeKeyAndOrderFront(nil)`; otherwise it
creates and shows the window. The window uses `NSWindow.isReleasedWhenClosed =
false` so the instance survives a close and the user can re-open it without
re-allocating the instance.

Settings edits are held in a local `@Observable` `SettingsViewModel` (draft
state). Save writes to `LockSettings` then closes the window. Cancel discards
the draft and closes. The `SettingsViewModel` is re-initialised from
`LockSettings` each time `showOrFocus()` is called, so the form always opens
with current persisted values.

`AppDelegate` is the only object that creates `SettingsWindowController`; it
passes the same `LockSettings` instance used by `MenuBarController`. This is
not a global singleton; it is held by `AppDelegate`.

### Decision 6 — Two-zone slider mapping

The slider stores a 0...1 `Double` (`sliderPosition`) and maps to one of 21
discrete values through a pure function `TwoZoneSlider.durationForPosition(_:)`.
The inverse mapping `TwoZoneSlider.positionForDuration(_:)` is used to
initialise `sliderPosition` from a stored `TimeInterval`. Both functions are
defined in a new `TwoZoneSlider.swift` utility file (no UI imports) and
unit-tested.

Zone table:
- Short zone: steps 0–11 → 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 s
  (12 steps, 5 s each)
- Long zone: steps 12–20 → 120, 180, 240, 300, 360, 420, 480, 540, 600 s
  (9 steps, 60 s each)

The 21 discrete values correspond to slider positions 0/20, 1/20, ..., 20/20.
A SwiftUI `Slider(value:in:step:)` with `in: 0...1, step: 1/20` plus an
`.onChange` that snaps the value to the nearest 1/20 increment handles this
natively; no custom slider component is needed.

The Settings view uses this slider. The quick-pick presets (15 s, 30 s, 60 s,
120 s) are fixed constants that do not go through the slider.

## Alternatives considered

### Alternative A — Separate HUDPresenting protocol (REJECTED)

A second protocol `HUDPresenting` with `showHUD(settings:)` and `hideHUD()`
alongside `LockPresenting`. `LockManager` would hold an optional
`AnyObject & HUDPresenting` and call it when `overlayMode == .hud`.

**Rejected** because it pushes overlay-mode logic into `LockManager`, which
already has the no-UI invariant (ADR-001 D3). The overlay controller is the
right place to decide what to render; `LockManager` should not inspect settings
to choose a presenter behavior. The `configure(settings:)` extension on the
existing protocol achieves the same branching at zero cost to `LockManager`.

### Alternative B — NSPopover stays, Settings is a second popover tab (REJECTED)

Keep the existing slider popover for left-click; add a gear button inside it
that reveals a Settings tab in the same popover.

**Rejected** because NSPopover is poorly suited for sidebar navigation on
macOS. The SPEC explicitly specifies a macOS Settings-style window with a
sidebar; a Settings window is the platform-idiomatic pattern (NSPanel +
`NavigationSplitView`). Retiring the popover also simplifies
`MenuBarController` — there is no longer a popover lifecycle to manage — and
the quick-pick menu is faster to reach than opening a popover.

### Alternative C — Read settings into LockManager at startLock time via a full LockSettings value (REJECTED for trackpadMode)

Pass the full `LockSettings` struct to `startLock(duration: settings:)`.

**Rejected** because it changes the frozen `startLock(duration:)` signature,
which ADR-001 D4 and the anchor-preservation constraint prohibit. The minimal
alternative (inject a `@Sendable () -> TrackpadMode` closure) gives `LockManager`
exactly the one piece of data it needs without widening the API or importing
`LockSettings` into the core.

### Alternative D — Discrete Picker for duration instead of two-zone slider (REJECTED)

Use a SwiftUI `Picker` / list with the 21 labeled values.

**Rejected** because the SPEC explicitly specifies a slider with two-zone
snapping. A picker would satisfy the discrete-steps requirement without any
mapping math, but it changes the intended UX. The two-zone mapping function
is small and fully unit-testable, so the implementation cost is low.

### Alternative E — Store OverlayMode / TrackpadMode as Int in UserDefaults (REJECTED)

Raw integers are fragile if enum cases are reordered. `String` raw values are
self-documenting in the plist and survive reordering safely. Cost is identical.
**Rejected** in favor of `String` raw values.

## Consequences

### Positive

- `LockManager` public API (`startLock(duration:)`, `unlock()`) is unchanged;
  all existing unit tests continue to compile and pass without modification
  (subject to the fake's `install()` signature update).
- The `LockPresenting` extension pattern absorbs the new `configure(settings:)`
  with zero source changes to existing conformers.
- The two-zone slider mapping function is pure and fully unit-testable; no
  SwiftUI or AppKit dependency in `TwoZoneSlider.swift`.
- Settings window re-use avoids memory churn; draft state prevents partial saves.
- Retiring `TimerPickerView` / `NSPopover` removes a lifecycle complexity from
  `MenuBarController`.
- Quick-pick menu is faster to reach than opening a popover.

### Negative

- `EventTapControlling.install()` signature change propagates to all test fakes.
  The full test suite must be run after this change; 5 `TimerPickerViewModelTests`
  must be removed or repurposed.
- `LockOverlayController` becomes more complex: it now handles three rendering
  modes (full-screen black, HUD with cursor visible, HUD rebuilds on display
  change). The `screensChanged()` handler must respect current overlay mode.
- The HUD window level needs a separate decision: HUD panels should use a level
  below `.screenSaver` but above normal windows so they are visible but not
  blocking the user's trackpad-free workflow. `.statusBar` is the chosen level.
- Trackpad-free mode: the cursor must remain visible. `LockOverlayController.present()`
  currently calls `CGDisplayHideCursor` and `NSCursor.hide()`. These must be
  skipped when `trackpadMode == .free`. `configure(settings:)` controls this.
- Retiring `TimerPickerView` loses the ability to set an arbitrary duration at
  lock time. A user who wants 47 s must go to Settings first. The SPEC calls
  for this simplification.

### Neutral

- `LockSettings` grows from 1 to 4 persisted keys. No migration needed; missing
  keys fall back to defaults at read time.
- `AppDelegate` gains a second strong reference (`SettingsWindowController`)
  alongside `MenuBarController`. The pattern matches how `MenuBarController` is
  already held.
- The quick-pick menu's fifth "custom default" item is conditional on a simple
  set-membership check. The fixed presets are `{15, 30, 60, 120}` seconds.

## References

- /Users/stefanoferri/Developer/Apple/CleanKey/SPEC.md §"Feature: Settings and Quick-Pick Lock"
- /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-001-cleankey-keyboard-touchpad-lock.md
- /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md
- Apple: NSStatusItem, NSMenu, NSMenu.popUpContextMenu(_:with:for:)
- Apple: NavigationSplitView (SwiftUI, macOS 13+)
- Apple: CGEventTapCreate, CGEventType raw values for gesture events
