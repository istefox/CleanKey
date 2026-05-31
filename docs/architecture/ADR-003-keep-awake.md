# ADR-003 — Keep-Awake (Sleep Prevention) Feature

## Status

Accepted — 2026-05-31

## Context

CleanKey v1.1 is a menu-bar agent that locks keyboard/trackpad input for a
duration (ADR-001) and exposes a Settings window plus quick-pick lock menu
(ADR-002). SPEC-keep-awake.md adds a second, independent capability:
Caffeine/Amphetamine-style sleep prevention. A single agent should cover both
locking and keep-awake, sharing one status item and one Settings window.

Keep-awake means holding two `IOPMAssertion` values (one preventing display
sleep, one preventing idle system sleep) for as long as the user wants,
optionally bounded by a duration cap (1 h–12 h), with a notification when the
machine goes onto battery while keep-awake is active.

This is a brownfield, additive feature. The following are non-negotiable
anchors carried from ADR-001/ADR-002 and the PRIOR AGENT NOTES:

- `LockManager` is UI-free and the sole owner of its CGEventTap + timer +
  watchdog. Its public API (`startLock(duration:)`, `unlock()`) is frozen and
  must not change for this feature.
- C-level system APIs are wrapped behind a small injected protocol so the owning
  manager is unit-testable without the real API (the `EventTapControlling`
  pattern). Keep-awake must follow the same idiom for `IOPMAssertion`.
- The `LockPresenting` and `EventTapControlling` protocols and the `LockSettings`
  struct must not change unless strictly necessary for this feature. Nothing in
  keep-awake requires touching them.
- Swift 6 strict concurrency. All new manager/coordinator/monitor types are
  `@MainActor`.
- App Sandbox is OFF for the DMG build; sandbox-incompatible calls are gated
  behind `#if APP_STORE_BUILD` for a future MAS path (ADR-001 D5).

Six design questions with long-term impact are decided below.

## Decision

### Decision 1 — Reject the AppCoordinator mediator; adopt parallel peers

`KeepAwakeManager` is a standalone `@MainActor` class instantiated by
`AppDelegate` alongside the existing lock stack, exactly as the SPEC's original
direction describes (BRAINSTORM Alternative A). There is **no** `AppCoordinator`
mediator (BRAINSTORM Alternative B) and **no** `FeatureManaging` protocol
(BRAINSTORM Alternative C).

Rationale. The only concrete job a coordinator would do in v1.1 is derive a
4-state menu-bar icon from two booleans. That derivation is a two-line `switch`
(Decision 3) and belongs in `MenuBarController`, which already owns the status
item and already derives its icon from a single `locked: Bool`. Introducing a
coordinator now buys a single observation point and a "future home for
cross-feature logic" that the SPEC explicitly lists as out of scope (presets,
scheduling). That is speculative future-proofing beyond the stated requirements,
and it carries a real god-object risk. The mediator earns its keep only when a
third feature or a genuine cross-feature interaction (e.g. a "Presentation mode"
preset that toggles both) lands. ADR §Future extensions names `AppCoordinator`
as the designated insertion point at that time, so the option is preserved, not
foreclosed.

The re-render-storm concern raised in the BRAINSTORM pre-mortem does not apply:
the menu bar is plain AppKit (`NSStatusItem`), updated by direct imperative
calls from `MenuBarController`, not by SwiftUI observation. There is no SwiftUI
diff cycle to coalesce. `MenuBarController` already calls `setMenuBarIcon` from
the presenter proxy's `onPresent`/`onDismiss` callbacks; keep-awake adds two
symmetric callbacks. No `@Observable` bridge is involved on the menu-bar path.

### Decision 2 — KeepAwakeManager interface and the IOPMAssertion wrapper protocol

`KeepAwakeManager` mirrors `LockManager`'s shape: a `@MainActor` class with all
side-effecting C calls injected behind protocols, so its state machine is
unit-testable with fakes and no real IOKit calls.

Public surface:

```
@MainActor
public final class KeepAwakeManager {
    public private(set) var isActive: Bool { get }   // derived from held assertion handle
    public func enable()                              // idempotent: no-op if already active
    public func disable()                             // idempotent: no-op if already inactive
    // injected seams (see protocols below) + an onChange callback for the menu bar
}
```

The IOPMAssertion C API is wrapped behind a new protocol, modelled on
`EventTapControlling`:

```
@MainActor
public protocol SleepAssertionControlling: AnyObject {
    /// Creates display-sleep + idle-system-sleep assertions. Returns false on failure.
    func createAssertions(reason: String) -> Bool
    func releaseAssertions()
    var isHeld: Bool { get }
}
```

`RealSleepAssertionController` (production) calls
`IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, ...)`
and `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
...)`, stores the two `IOPMAssertionID` values, and releases both in
`releaseAssertions()`. It is the **single owner** of the two assertion IDs — they
are never copied out, mirroring the "single owner, never copy the pointer"
invariant for the tap context (ADR-001 D6). On any `createAssertions` failure it
releases whichever assertion succeeded and returns `false`, so the app never
leaks a half-created pair (SPEC §7: `IOPMAssertionCreate` fails → set inactive,
notify).

`KeepAwakeManager.isActive` is computed from the controller's `isHeld` (the
authoritative state lives with the assertion owner, not duplicated in the
manager). `enable()` calls `createAssertions`; on `false` it posts the
"Keep Awake unavailable" notification via the existing `Notifying` seam and
stays inactive. `disable()` calls `releaseAssertions`, tears down the cap timer
and the power-source observer, and writes `keepAwakeLastActiveState = false`.

Teardown order is fixed and documented (parallel to ADR-001's lock teardown):
**stop cap timer → stop power observer → release assertions → set state → fire
onChange**. The power observer and timer are stopped before the assertions are
released so a late callback can never fire against a half-torn-down manager.

A new no-op `IOPMAssertionType`-free fake (`FakeSleepAssertionController`) lands
in `TestHelpers.swift` for unit tests, recording create/release call counts and
a settable `createShouldFail` flag.

### Decision 3 — 4-state icon derived inline, no AppDisplayState enum

The SPEC §4.2 proposes an `AppDisplayState` enum bridge. It is **dropped**
(BRAINSTORM finding, confirmed here). `MenuBarController` derives the icon
directly from the two booleans it already tracks:

```
private func updateMenuBarIcon() {
    let name: String
    switch (isLocked, isAwake) {
    case (false, false): name = "menubar-unlocked"
    case (true,  false): name = "menubar-locked"
    case (false, true):  name = "menubar-awake"
    case (true,  true):  name = "menubar-locked-awake"
    }
    // load template NSImage(named:) with SF Symbol fallback, as today
}
```

`isLocked` is already maintained via the presenter proxy callbacks
(`onPresent` → true, `onDismiss` → false). `isAwake` is a new stored `Bool` on
`MenuBarController`, set from a `KeepAwakeManager.onChange` callback (symmetric
to how lock state reaches the controller). The existing `setMenuBarIcon(locked:)`
is replaced by `updateMenuBarIcon()` reading both flags; the title-clearing
behaviour (`statusItem.button?.title = ""` when idle) is preserved.

A four-value enum is not introduced because there is exactly one consumer
(`MenuBarController.updateMenuBarIcon`), the mapping is total and trivial, and a
named enum would add a type whose only method is the switch above. If a second
consumer ever appears, promoting `(isLocked, isAwake)` to a named enum is a
local refactor.

This is an **observable-contract change inside `MenuBarController`**:
`setMenuBarIcon(locked:)` is replaced. It is a private method with no external
call-sites (confirmed by grep: the only references are within
`MenuBarController.swift` — `setupStatusItem` and the two presenter-proxy
closures). No test asserts on it (grep for `setMenuBarIcon` across
`CleanKeyTests/` returns nothing). The icon path is verified by integration,
not unit tests.

### Decision 4 — Power-source monitoring lives in KeepAwakeManager, behind a protocol; no entitlement needed

Battery-unplug detection is owned by `KeepAwakeManager` (BRAINSTORM: a shared
`PowerSourceMonitor` service is YAGNI for one consumer). The C API
(`IOPSNotificationCreateRunLoopSource` + `IOPSCopyPowerSourcesInfo`) is wrapped
behind a third small protocol so the manager stays testable:

```
@MainActor
public protocol PowerSourceObserving: AnyObject {
    /// Starts observing; calls `onChange(isOnBattery:)` when the source changes.
    func start(onChange: @escaping (_ isOnBattery: Bool) -> Void)
    func stop()
}
```

`RealPowerSourceObserver` creates the run-loop source, adds it to
`CFRunLoopGetMain()` in `.commonModes`, and on each callback reads
`IOPSCopyPowerSourcesInfo` / `IOPSGetProvidingPowerSourceType` to decide
on-battery vs on-AC. It is the single owner of the `CFRunLoopSourceRef`: it
removes the source from the run loop and invalidates it in `stop()`. The
observer is started by `KeepAwakeManager.enable()` and stopped by `disable()`,
so it only runs while keep-awake is active.

Behaviour on the callback: if `isActive && isOnBattery`, post a notification
"Keep Awake is active on battery — tap to disable". This does **not**
auto-disable keep-awake (SPEC §5.2). Tapping the notification calls `disable()`.

Entitlement / sandbox finding (confirms the BRAINSTORM open question): both
`IOPMAssertionCreateWithName` and `IOPSNotificationCreateRunLoopSource` are
public IOKit power-management APIs that require **no special entitlement** on
macOS 14+ when App Sandbox is OFF, which is CleanKey's DMG configuration
(ADR-001 D5). No change to `CleanKey.entitlements` is required for this feature.
For a future MAS build (sandbox ON), these calls remain available to sandboxed
apps; should a specific assertion type be restricted under sandbox, the create
call is gated behind the existing `#if APP_STORE_BUILD` flag — but no such gate
is added speculatively now.

### Decision 5 — UNUserNotificationCenter: confirmed no Info.plist usage string needed; add a delegate for tap handling

Confirmed by reading `CleanKey/Info.plist`: there is **no** notification-related
key today, and none is required. Local notifications via
`UNUserNotificationCenter` do not use an `Info.plist` usage-description key
(that mechanism is for privacy-sensitive resources like camera/location).
Authorization is requested at runtime via
`UNUserNotificationCenter.current().requestAuthorization(options:)`. The
BRAINSTORM's "confirm it is absent and add it" note resolves to: nothing to add
to `Info.plist`.

A new `KeepAwakeNotifier` type wraps `UNUserNotificationCenter` behind a tiny
protocol so `KeepAwakeManager` does not import `UserNotifications` directly and
stays testable:

```
public protocol BatteryWarningNotifying: AnyObject {
    func requestAuthorizationIfNeeded()
    func postBatteryWarning()
    func clearBatteryWarning()
}
```

`requestAuthorizationIfNeeded()` is called once on first `enable()`. If
authorization is denied, `postBatteryWarning()` is a silent no-op (SPEC §7:
permission denied → warning skipped, no crash). The real implementation sets a
`UNUserNotificationCenterDelegate` so that tapping the notification action
routes back to `KeepAwakeManager.disable()`. The delegate is owned by the real
notifier; the action identifier is a private constant.

This is distinct from the lock feature's `Notifying`/`ConsoleNotifier` seam,
which only logs. Keep-awake needs a user-visible banner with a tap action, a
different responsibility, so it gets its own protocol rather than overloading
`Notifying`.

### Decision 6 — KeepAwakeSettings as a sibling of LockSettings; new Settings sidebar item

Persistence mirrors `LockSettings` exactly (computed `UserDefaults` properties,
`String`/`Double`/`Bool`, fallback defaults, no migration). The new keys live in
a separate `KeepAwakeSettings` struct (SPEC §8), keeping the lock and keep-awake
preference surfaces decoupled:

```
public struct KeepAwakeSettings: @unchecked Sendable {
    public var durationCap: TimeInterval   // seconds; 0 == no cap (indefinite)
    public var restoreOnLaunch: Bool       // default false
    public var lastActiveState: Bool       // written on enable/disable
}
```

Keys (SPEC §8): `keepAwakeDurationCap` (Double, default 0),
`keepAwakeRestoreOnLaunch` (Bool, default false), `keepAwakeLastActiveState`
(Bool, default false). Allowed cap values: 0 (no limit), 3600, 7200, 14400,
28800, 43200 s. A `clampCap(_:)` static helper snaps to the nearest allowed
value (the constant set, not literals scattered in views — the same lesson as
`LockSettings.minimumDuration`).

The Settings window gains a third sidebar item. `SettingsSidebarItem` (currently
`general`, `display`) gets a `keepAwake` case; `SettingsView` adds the
`KeepAwakeSettingsView` detail branch. The existing `SettingsViewModel` gains
two bindable draft properties (`keepAwakeDurationCap`, `keepAwakeRestoreOnLaunch`)
and its `init(settings:)` / `save(to:)` are extended to read/write
`KeepAwakeSettings`. Because `save(to:)` currently takes `inout LockSettings`,
the view model's save gains a second parameter
`save(to:keepAwake:)` or a separate `saveKeepAwake(to:)` — see the contract note
below.

Observable-contract change — `SettingsViewModel.save(to:)` and
`SettingsView`/`SettingsSidebarItem`. Grep results across the codebase for the
affected symbols:

- `SettingsViewModel.save(to:)` — sole call-site is
  `CleanKey/SettingsWindowController.swift:35` (`viewModel.save(to: &self.settings)`).
  `SettingsWindowController` must hold and pass a `KeepAwakeSettings` instance
  too. Decision: add a separate method `saveKeepAwake(to: inout KeepAwakeSettings)`
  rather than widening `save(to:)`, so the existing call-site and the four
  `SettingsViewModelTests` asserting `save(to:)` behaviour keep compiling
  unchanged; the controller calls both.
- `SettingsSidebarItem` — referenced in `CleanKey/Views/SettingsView.swift`
  only (`allCases` drives the sidebar; the `switch selection` builds the detail).
  Adding a `.keepAwake` case requires updating the `switch` in `body` and the
  `systemImage(for:)` switch in the same file (Swift will flag both as
  non-exhaustive — the compiler is the call-site finder here).
- No test references `SettingsSidebarItem` (grep of `CleanKeyTests/` is empty),
  so no test update is forced by the enum change.

The full test suite is run after the `SettingsViewModel` change because the view
model is shared with the lock feature's settings.

## Alternatives considered

### Alternative A — Parallel peers (ADOPTED)

`KeepAwakeManager` standalone alongside `LockManager`; `AppDelegate` owns both;
`MenuBarController` derives the icon inline from `isLocked` and `isAwake`. See
Decision 1 and Decision 3. **Adopted** because it adds the fewest new types,
matches the existing structure (two peer managers owned by the app, each
self-contained and independently testable), and the only cross-feature concern
in scope (icon derivation) is a trivial total `switch` with one consumer. It
keeps the two managers fully decoupled — neither imports nor references the
other — which is the cleanest possible seam.

### Alternative B — AppCoordinator mediator (REJECTED)

A new `@Observable AppCoordinator`, owned by `AppDelegate`, holding both
managers and acting as the single source of truth for the menu bar;
`MenuBarController` observes only the coordinator; the coordinator derives the
display state and can debounce re-renders and host future cross-feature logic.

**Rejected** for v1.1 because its concrete benefits do not yet exist. (1) The
"single observation point" gain is moot: the menu bar is imperative AppKit, not
SwiftUI, so there is no observation graph and no re-render storm to coalesce
(the pre-mortem risk is inapplicable). (2) The "future home for cross-feature
logic" serves presets and scheduling, both explicitly out of scope per SPEC §2;
building the home before the tenant is speculative future-proofing. (3) It adds
a type whose only v1.1 responsibility is a two-line switch that already has a
natural owner. (4) The god-object risk is real and the mitigation (a strict
derive-only contract) is overhead to enforce for zero present benefit. The
option is preserved: ADR §Future extensions names `AppCoordinator` as the
designated insertion point when a preset or scheduler actually arrives, at which
point it will have real work to justify it.

### Alternative C — Protocol-unified FeatureManaging (REJECTED)

Extract a `FeatureManaging` protocol (`enable()`, `disable()`, `isActive`); both
managers conform; `AppDelegate` holds `[any FeatureManaging]` and derives the
icon by iterating.

**Rejected** as premature abstraction with only two conformers whose lifecycles
differ substantially (lock: timer + event tap + escape combo + wall-clock expiry;
keep-awake: two assertions + cap timer + power observer). A homogeneous array
loses the per-feature type information needed for configuration and makes the
4-state icon harder to derive (you cannot pattern-match `(isLocked, isAwake)`
from a `[any FeatureManaging]` without re-discovering which element is which).
`LockManager.startLock(duration:)` does not even share `enable()`'s nullary
shape, so the uniform interface is a poor fit. Same family of objection as
ADR-002 Alternative A (parallel protocol hierarchy adds cost to the core for no
gain).

### Alternative D — Single combined assertion (PreventUserIdleSystemSleep only) (REJECTED)

Hold one `IOPMAssertion` of type `PreventUserIdleSystemSleep` and rely on it to
keep the display awake too.

**Rejected** because `PreventUserIdleSystemSleep` prevents idle *system* sleep
but does **not** prevent the *display* from sleeping; the screen can still dim
and turn off while the machine stays awake. The SPEC §2 requires preventing both
display sleep and system sleep, which is exactly the Caffeine behaviour and
requires the two-assertion pair (`PreventUserIdleDisplaySleep` +
`PreventUserIdleSystemSleep`). The cost of the second assertion is negligible
and the single-owner controller releases both atomically.

### Alternative E — Store the AppDisplayState enum as designed in the SPEC (REJECTED)

Keep SPEC §4.2's `AppDisplayState` enum as a bridge type that both managers feed
and `MenuBarController` observes.

**Rejected** in favour of inline derivation (Decision 3). The enum has exactly
one consumer and a total, trivial mapping; a named type whose only purpose is to
be switched over once adds indirection without abstraction value. The two source
booleans already exist on `MenuBarController`. Promoting to a named enum is a
cheap local refactor if a second consumer ever appears, so nothing is lost by
deferring it.

### Alternative F — Auto-disable keep-awake on battery (REJECTED)

When the machine goes onto battery while keep-awake is active, automatically
call `disable()` instead of (or in addition to) notifying.

**Rejected** because it contradicts SPEC §5.2 ("does NOT auto-disable"). A user
may deliberately keep the machine awake on battery (e.g. a long download). The
correct behaviour is to inform and let the user decide via the notification's
tap action. Documented here so the implementer does not "helpfully" add the
auto-disable.

## Consequences

### Positive

- `LockManager`, `LockPresenting`, `EventTapControlling`, and the `LockSettings`
  struct are untouched. All existing lock/watchdog/settings/slider/sound tests
  compile and pass without modification. The anchor-preservation constraint is
  fully honoured.
- `KeepAwakeManager` is a structural twin of `LockManager`: `@MainActor`, C APIs
  behind injected protocols, single-owner of its OS handles, fixed teardown
  order, fully unit-testable with fakes. Reviewers already know this shape.
- Three small, single-purpose protocols (`SleepAssertionControlling`,
  `PowerSourceObserving`, `BatteryWarningNotifying`) keep IOKit and
  UserNotifications out of the testable core and give each side effect an
  obvious fake.
- No new entitlement and no `Info.plist` change — the DMG signing/notarization
  path is unaffected.
- Lock and keep-awake are genuinely independent: neither manager references the
  other, so a bug in one cannot regress the other. The icon switch is the only
  point where the two states meet, and it is read-only.
- The `AppCoordinator` option is preserved and named for the moment it earns its
  place (presets / scheduling), so deferring it is not a one-way door.

### Negative

- `KeepAwakeManager` and the three controllers can only be fully verified on
  hardware (real sleep prevention, real battery-unplug callback, real
  notification banner). Unit tests cover the state machine and the fakes; SPEC
  success criteria #1, #3, #7 ("verified via `pmset -g assertions`") and the
  battery banner are an integration/manual checklist item.
- Two `@MainActor` managers plus three controllers and a notifier add five new
  types to `AppDelegate`'s construction graph. Construction order matters
  (`KeepAwakeManager` before `MenuBarController` so the latter can wire the
  `onChange` callback). Documented in the plan.
- `SettingsViewModel` is now shared between two settings structs. A change to its
  shape touches both the lock and keep-awake settings paths, so the full suite
  must run after every change to it.
- `MenuBarController` grows a second state flag (`isAwake`) and a new menu item
  pair (Enable/Disable Keep Awake). The right-click context menu gains an entry;
  the controller's menu-building code grows modestly.
- Crash/force-quit while keep-awake is active leaks the assertions until reboot
  or until the OS reaps them on process exit. `IOPMAssertion` IDs are released by
  the kernel when the owning process dies, so a hard crash does not keep the Mac
  awake indefinitely — but `applicationWillTerminate` must still call
  `disable()` for clean shutdown (SPEC §7), and the plan adds an `atexit`-style
  safety release as belt-and-braces (BRAINSTORM risk R2).

### Neutral

- `UserDefaults` grows by three keys (`keepAwakeDurationCap`,
  `keepAwakeRestoreOnLaunch`, `keepAwakeLastActiveState`). No migration; absent
  keys read as their declared defaults, same as every other CleanKey setting.
- The duration cap is silent: no countdown in the status-item title (SPEC §5.1),
  unlike the lock countdown. Showing it is a named future extension.
- `KeepAwakeManager.enable()`/`disable()` are nullary and idempotent, matching
  the SPEC's toggle semantics; they deliberately do not share `LockManager`'s
  `startLock(duration:)` shape (see Alternative C).
- The cap timer reuses the wall-clock discipline (ADR-001): it computes an
  `endsAt: Date` and a single `Timer`, so a cap survives the same sleep/wake
  reasoning as the lock countdown (though in practice keep-awake prevents the
  idle sleep that would test it).

### Future extensions (named hooks, not implemented)

- **"Presentation mode" preset** — one action toggling both lock and keep-awake.
  This is the trigger that justifies introducing `AppCoordinator` (Alternative B):
  a preset is a genuine cross-feature interaction needing a single owner. Until
  then, no coordinator.
- **Scheduled keep-awake** — auto-enable between configured hours. Natural home
  is the future `AppCoordinator`; `KeepAwakeManager.enable()`/`disable()` are
  the actuators it would call.
- **Cap countdown in status title** — show remaining cap time (e.g. "3h 22m") in
  the title, mirroring the lock countdown. Reuses the `PresenterProxy.onTick`
  pattern; `KeepAwakeManager` would gain an `onTick` callback fed by the cap
  timer. Not built now (SPEC §5.1 keeps the cap silent).

## References

- /Users/stefanoferri/Developer/Apple/CleanKey/SPEC-keep-awake.md
- /Users/stefanoferri/Developer/Apple/CleanKey/BRAINSTORM-keep-awake.md
- /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-001-cleankey-keyboard-touchpad-lock.md
- /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-002-settings-quick-pick.md
- /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md
- Apple: IOPMAssertionCreateWithName, kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionTypePreventUserIdleSystemSleep, IOPMAssertionRelease
- Apple: IOPSNotificationCreateRunLoopSource, IOPSCopyPowerSourcesInfo, IOPSGetProvidingPowerSourceType
- Apple: UNUserNotificationCenter, UNUserNotificationCenterDelegate, requestAuthorization(options:)
