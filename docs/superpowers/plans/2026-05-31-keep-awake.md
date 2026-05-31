# Plan — Keep-Awake (Sleep Prevention) Feature (TDD)

- **Date:** 2026-05-31
- **Mode:** brownfield
- **SPEC:** /Users/stefanoferri/Developer/Apple/CleanKey/SPEC-keep-awake.md
- **ADR:** /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-003-keep-awake.md
- **BRAINSTORM:** /Users/stefanoferri/Developer/Apple/CleanKey/BRAINSTORM-keep-awake.md
- **ARCH:** /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md (no changes — additive decisions are in ADR-003)
- **Stack:** Swift 6 (strict concurrency), macOS 14+, SwiftUI + AppKit, IOKit (IOPMAssertion + IOPSNotification), UserNotifications.
- **Test command:** `xcodebuild test -scheme CleanKey -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`

## Conventions for the implementer

- Conventional Commits in English. Feature branch `feat/keep-awake`, never commit to `main`.
- HITL gate before: `git commit`, `git push`, permanent deletions, schema/entitlement changes, GitHub Release.
- TDD: write the failing test first, then minimal implementation, then refactor.
  IOKit-bound, notification-bound, and UI-bound code is verified by integration/manual tests, not unit tests; its state machine is unit-tested via injected fakes.
- All new manager/controller/observer types are `@MainActor` and Swift 6 strict-concurrency clean.
- C system APIs are wrapped behind a protocol (the `EventTapControlling` idiom); never call IOKit directly from a manager.
- Anchor-preserving: do NOT modify `LockManager`, `LockPresenting`, `EventTapControlling`, or the `LockSettings` struct. If a task appears to need one of these changed, stop and escalate.
- Run the **full test suite** after every task that touches a shared/public contract (`SettingsViewModel`, `TestHelpers`).
- Any helper script must be Bash 3.2-clean (no `mapfile`, no `${var^^}`, no associative arrays).
- Do not modify `docs/manifests/*.manifest.yml` or `.remember/**`.

---

## Task 1 — KeepAwakeSettings persistence struct

**Goal:** a `KeepAwakeSettings` struct sibling to `LockSettings`, persisting
`durationCap`, `restoreOnLaunch`, `lastActiveState` via `UserDefaults` computed
properties with fallback defaults and a `clampCap` helper.

Files to create:
- `CleanKey/KeepAwakeSettings.swift` — `public struct KeepAwakeSettings:
  @unchecked Sendable` with the same `init(defaults: UserDefaults = .standard)`
  pattern as `LockSettings`. Keys: `keepAwakeDurationCap` (Double, default 0 =
  no cap), `keepAwakeRestoreOnLaunch` (Bool, default false),
  `keepAwakeLastActiveState` (Bool, default false). Static
  `allowedCaps: [TimeInterval] = [0, 3600, 7200, 14400, 28800, 43200]` and
  `static func clampCap(_:) -> TimeInterval` snapping to the nearest allowed
  value. Expose `durationCap` get/set through `clampCap`.

Files to modify:
- `CleanKey.xcodeproj/project.pbxproj` — add the new file to the app target AND
  the test target (so unit tests can `@testable import` it).

Tests to write first (`CleanKeyTests/KeepAwakeSettingsTests.swift` — new file,
Swift Testing per the Swift 6 rule, matching existing suite style if those are
XCTest — match whatever `LockSettingsTests.swift` uses):
- Defaults with a fresh `UserDefaults(suiteName:)`: `durationCap == 0`,
  `restoreOnLaunch == false`, `lastActiveState == false`.
- Round-trip: set `durationCap = 7200`, `restoreOnLaunch = true`,
  `lastActiveState = true`; reload from same suite; values persist.
- `clampCap` snaps an off-list value (e.g. 5000) to the nearest allowed cap and
  references `allowedCaps`, never a literal.
- Setting `durationCap` to a non-allowed value reads back as the clamped value.

No HITL. No contract change (new struct, no existing call-sites).

---

## Task 2 — SleepAssertionControlling protocol + RealSleepAssertionController

**Goal:** wrap the two `IOPMAssertion` calls behind a testable protocol owned by
the production controller. No `KeepAwakeManager` yet.

Files to create:
- `CleanKey/KeepAwakeProtocols.swift` — `@MainActor public protocol
  SleepAssertionControlling: AnyObject { func createAssertions(reason: String)
  -> Bool; func releaseAssertions(); var isHeld: Bool { get } }`. (This file
  will also hold `PowerSourceObserving` in Task 4 and `BatteryWarningNotifying`
  in Task 5 — create it now with just the assertion protocol.)
- `CleanKey/RealSleepAssertionController.swift` — `@MainActor final class
  RealSleepAssertionController: SleepAssertionControlling`. Holds two optional
  `IOPMAssertionID`. `createAssertions` calls
  `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as
  CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)`
  and the same for `kIOPMAssertionTypePreventUserIdleSystemSleep`. On any
  failure (non-`kIOReturnSuccess`), release whichever succeeded and return
  `false`. `releaseAssertions` calls `IOPMAssertionRelease` on each held id and
  nils them. `isHeld` is `displayID != nil && systemID != nil`. Single owner —
  ids never escape the class.

Files to modify:
- `CleanKey.xcodeproj/project.pbxproj` — add both files to the app target;
  add `KeepAwakeProtocols.swift` to the test target.

Tests: the real controller cannot be unit-tested without affecting the machine's
sleep state. Add `FakeSleepAssertionController` to `TestHelpers.swift` now (used
by Task 3 tests):
- `FakeSleepAssertionController`: `createCallCount`, `releaseCallCount`,
  `createShouldFail: Bool`, and `isHeld` derived from create/release balance and
  the fail flag. This is a **change to the shared `TestHelpers.swift`** — run the
  **full test suite** after adding it to confirm no compile regression in the
  existing fakes.

Integration/manual (deferred to Task 8): `pmset -g assertions` shows both
`PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep` while active, and
neither after release.

---

## Task 3 — KeepAwakeManager state machine (enable/disable/isActive + cap timer)

**Goal:** the `@MainActor KeepAwakeManager` with injected seams, idempotent
`enable()`/`disable()`, `isActive` derived from the assertion controller, the
duration-cap timer, and the `onChange` callback for the menu bar. Power observer
and battery notifier are injected but their wiring is exercised in Tasks 4–5; in
this task they are stubbed via fakes.

Files to modify:
- `CleanKey/KeepAwakeProtocols.swift` — (no change unless Task 4/5 protocols are
  pulled forward; keep them in their own tasks).

Files to create:
- `CleanKey/KeepAwakeManager.swift` — see ADR-003 Decision 2. Injected:
  `clock: @Sendable () -> Date` (default `{ Date() }`, mirrors `LockManager`),
  `assertions: SleepAssertionControlling`, `powerObserver: PowerSourceObserving`,
  `notifier: BatteryWarningNotifying`,
  `capProvider: @Sendable () -> TimeInterval` (reads `KeepAwakeSettings.durationCap`),
  `onChange: @escaping () -> Void` (menu bar hook),
  `persist: @escaping (Bool) -> Void` (writes `lastActiveState`).
  `isActive` returns `assertions.isHeld`. `enable()`: guard not already held;
  call `notifier.requestAuthorizationIfNeeded()`; if
  `assertions.createAssertions(reason:)` is false → `notifier`-route a
  "Keep Awake unavailable" message (via the existing `Notifying`/`Logger` seam —
  see note) and return; start power observer; if `capProvider() > 0` start cap
  timer with `endsAt = clock() + cap`; `persist(true)`; `onChange()`.
  `disable()`: guard held; **fixed teardown order: stop cap timer → power
  observer stop → assertions.releaseAssertions() → persist(false) → onChange()**.
  Cap timer fire → call `disable()`.
  Power observer `onChange(isOnBattery:)` → if `isActive && isOnBattery` call
  `notifier.postBatteryWarning()`; never auto-disable (SPEC §5.2).
  Note on the "unavailable" message: reuse the existing `Notifying` log seam for
  the developer log; the user-facing banner is `BatteryWarningNotifying`. Keep
  the two notifiers distinct (ADR-003 D5).

Tests to write first (`CleanKeyTests/KeepAwakeManagerTests.swift` — new file),
all using fakes (`FakeSleepAssertionController`, plus `FakePowerSourceObserver`
and `FakeBatteryWarningNotifier` added to `TestHelpers.swift` in this task):
- `enable()` from idle → `createCallCount == 1`, `isActive == true`,
  `onChange` fired once, `persist(true)` recorded, power observer started.
- `enable()` when already active → no-op (`createCallCount` stays 1).
- `disable()` from active → `releaseCallCount == 1`, `isActive == false`,
  power observer stopped, `persist(false)`, `onChange` fired. Assert teardown
  order via a shared call-log if feasible (stop-observer before release).
- `disable()` when already idle → no-op.
- `enable()` with `createShouldFail = true` → `isActive == false`, no power
  observer started, "unavailable" path taken.
- Cap timer: with `capProvider = { 3600 }` and an injected clock, simulate
  `endsAt` reached → manager calls `disable()` (drive via the same
  test-injectable tick entry point pattern as `LockManager.watchdogTick`;
  expose a `capTimerFired()` internal method called by the real `Timer`).
- Power callback: `enable()` then fake fires `onChange(isOnBattery: true)` →
  `postBatteryWarning` called once; manager still active (no auto-disable).
- Power callback `isOnBattery: false` while active → no warning posted.

This task adds three fakes to `TestHelpers.swift` (shared contract): run the
**full test suite** after.

---

## Task 4 — PowerSourceObserving protocol + RealPowerSourceObserver

**Goal:** the real battery/AC observer wrapping
`IOPSNotificationCreateRunLoopSource`, owned single-source-of-truth.

Files to modify:
- `CleanKey/KeepAwakeProtocols.swift` — add `@MainActor public protocol
  PowerSourceObserving: AnyObject { func start(onChange: @escaping (Bool) ->
  Void); func stop() }`.

Files to create:
- `CleanKey/RealPowerSourceObserver.swift` — `@MainActor final class`. `start`
  creates the run-loop source via `IOPSNotificationCreateRunLoopSource` with a
  C callback that bounces to the stored Swift closure on the main run loop;
  adds it to `CFRunLoopGetMain()` in `.commonModes`. The callback reads
  `IOPSCopyPowerSourcesInfo()` + `IOPSGetProvidingPowerSourceType()` and maps to
  `isOnBattery`. `stop` removes the source from the run loop and invalidates it,
  nils the stored ref. Single owner of the `CFRunLoopSourceRef`. Use the same
  `@unchecked Sendable` context-box discipline as `RealEventTapController`'s
  `TapContext` to pass `self` to the C callback safely.

Files to modify:
- `CleanKey.xcodeproj/project.pbxproj` — add `RealPowerSourceObserver.swift` to
  the app target.

Tests: the real observer needs hardware power events; defer to Task 8 manual
check (unplug → callback within 2 s). The fake (`FakePowerSourceObserver`,
added in Task 3) covers the manager's reaction logic. No unit test here.

No contract change (new file). No full-suite run required for this task alone.

---

## Task 5 — BatteryWarningNotifying protocol + KeepAwakeNotifier (UNUserNotificationCenter)

**Goal:** the user-facing battery banner with a tap action that calls back to
disable keep-awake. Confirm no `Info.plist` change is needed.

Files to modify:
- `CleanKey/KeepAwakeProtocols.swift` — add `public protocol
  BatteryWarningNotifying: AnyObject { func requestAuthorizationIfNeeded();
  func postBatteryWarning(); func clearBatteryWarning() }`.

Files to create:
- `CleanKey/KeepAwakeNotifier.swift` — `final class KeepAwakeNotifier: NSObject,
  BatteryWarningNotifying, UNUserNotificationCenterDelegate`. Wraps
  `UNUserNotificationCenter.current()`. `requestAuthorizationIfNeeded` requests
  `[.alert, .sound]` once (idempotent via a flag); sets itself as delegate;
  registers a category with a "Disable" action (identifier constant). If denied,
  `postBatteryWarning` is a silent no-op (SPEC §7). `postBatteryWarning` posts a
  banner "Keep Awake is active on battery — tap to disable". The delegate's
  `didReceive response` handler invokes a stored `onDisableRequested: () ->
  Void` closure (wired by `AppDelegate` to `keepAwakeManager.disable()`).

Files to modify:
- `CleanKey.xcodeproj/project.pbxproj` — add the file to the app target.

`Info.plist` confirmation (ADR-003 D5): local `UNUserNotificationCenter`
notifications need **no** usage-description key. Grep `CleanKey/Info.plist` to
confirm no notification key exists; do **not** add one. This is an explicit
"confirm absence" step, not an edit.

Tests: notification delivery is OS-bound — integration only (Task 8: unplug →
banner appears; tap → keep-awake disables). The manager's interaction with this
seam is already covered by `FakeBatteryWarningNotifier` (Task 3). No unit test
here.

---

## Task 6 — Menu bar: 4-state icon + Enable/Disable Keep Awake items

**Goal:** `MenuBarController` derives the icon inline from `(isLocked, isAwake)`
and gains the keep-awake menu item pair. Wire the `KeepAwakeManager.onChange`
callback into `isAwake`.

Observable-contract change inside `MenuBarController`:
`setMenuBarIcon(locked:)` is replaced by `updateMenuBarIcon()` reading two
flags. Grep results (run before editing, confirm still accurate):
- `setMenuBarIcon` — references only in `CleanKey/MenuBarController.swift`
  (`setupStatusItem` + the two presenter-proxy closures `onPresent`/`onDismiss`).
  No external call-site, no test asserts on it (grep `CleanKeyTests/` for
  `setMenuBarIcon` is empty).

Files to modify:
- `CleanKey/MenuBarController.swift`:
  - Add `private var isLocked = false`, `private var isAwake = false`.
  - Replace `setMenuBarIcon(locked:)` with `updateMenuBarIcon()` (4-way switch,
    ADR-003 D3); presenter-proxy `onPresent`/`onDismiss` set `isLocked` then call
    `updateMenuBarIcon()`. Preserve the title-clearing on idle.
  - Accept a `KeepAwakeManager` (injected at init) and set its `onChange` to
    `{ [weak self] in self?.isAwake = self?.keepAwakeManager.isActive ?? false;
    self?.updateMenuBarIcon() }`.
  - Right-click context menu: add a dynamic item — "Enable Keep Awake" when
    `!isAwake`, "Disable Keep Awake" when `isAwake` — its action calls
    `keepAwakeManager.enable()` / `disable()`. (Place above "Settings…".)
  - Add new template image asset names `menubar-awake` and
    `menubar-locked-awake` to the switch, with SF Symbol fallbacks
    (`sun.max` / a composed symbol).
- `CleanKey/Assets.xcassets` — add `menubar-awake` and `menubar-locked-awake`
  template image sets (18×18 pt). If art is not ready, ship SF Symbol fallbacks
  and flag the asset as a follow-up (do not block the task on final art).

Tests: icon rendering and NSMenu are AppKit/UI — integration only (Task 8). If a
pure helper is extracted for the icon-name mapping
(`iconName(locked:awake:) -> String`), unit-test it
(`CleanKeyTests/MenuBarIconTests.swift`): all four `(Bool, Bool)` combinations
map to the expected asset name. Recommended: extract that one pure function so
the 4-state logic has a unit test (cheap, matches the "pure-logic is testable"
discipline).

---

## Task 7 — AppDelegate wiring + restore-on-launch + clean teardown

**Goal:** `AppDelegate` constructs the keep-awake stack in the correct order,
wires the notifier's disable callback, restores on launch when opted in, and
releases assertions on quit.

Files to modify:
- `CleanKey/AppDelegate.swift`:
  - In `applicationDidFinishLaunching`: build `KeepAwakeSettings()`; construct
    `RealSleepAssertionController`, `RealPowerSourceObserver`, `KeepAwakeNotifier`;
    construct `KeepAwakeManager` with `capProvider: { keepAwakeSettings.durationCap }`,
    `persist: { keepAwakeSettings.lastActiveState = $0 }`, and an `onChange` that
    the `MenuBarController` overwrites (or pass the manager into
    `MenuBarController` and let it set `onChange`). Construct `MenuBarController`
    **after** `KeepAwakeManager` and pass it in.
  - Wire `keepAwakeNotifier.onDisableRequested = { [weak keepAwakeManager] in
    keepAwakeManager?.disable() }`.
  - Restore-on-launch (SPEC §4.5, §7): if
    `keepAwakeSettings.restoreOnLaunch && keepAwakeSettings.lastActiveState`,
    call `keepAwakeManager.enable()`. (Cap-already-expired edge: the cap timer
    starts fresh from launch; since the prior elapsed time is not persisted, a
    restored session restarts the cap. Document this in the manifest as accepted
    v1.1 behaviour; SPEC §7's "cap already expired → skip" is satisfied trivially
    because elapsed cap time is not tracked across launches, so we treat restore
    as a fresh enable. If stricter behaviour is wanted, persist `capEndsAt` —
    flagged as a follow-up, not built now.)
  - Add `applicationWillTerminate(_:)`: call `keepAwakeManager.disable()` so
    assertions are released cleanly (SPEC §7).
  - Hold strong references to `keepAwakeManager`, the three controllers, and the
    notifier (mirror the `menuBarController` strong-ref pattern).
  - Belt-and-braces (BRAINSTORM R2): register an `atexit`-safe release. Since
    `atexit` cannot capture `@MainActor` state safely under Swift 6, prefer
    relying on the kernel reaping `IOPMAssertion` on process exit (documented in
    ADR-003 Consequences) plus `applicationWillTerminate`. Only add an explicit
    `atexit` hook if a leak is observed in Task 8; otherwise skip it. Note this
    decision in the manifest.

Files to modify:
- `CleanKey/MenuBarController.swift` — `init` signature gains a
  `keepAwakeManager: KeepAwakeManager` parameter. Grep call-sites:
  `CleanKey/AppDelegate.swift:13` is the only constructor call; the convenience
  default-args `init` used by any test must keep compiling (add a default or a
  test-only convenience). Confirm no test constructs `MenuBarController`
  directly (grep `CleanKeyTests/` for `MenuBarController(` — expected empty; if
  not empty, update those call-sites).

Tests: AppDelegate wiring is integration (Task 8). Restore-on-launch logic, if
extracted into a pure helper (`shouldRestore(settings:) -> Bool`), is unit-tested
in `KeepAwakeManagerTests` or a small `AppLaunchTests`. Recommended extraction
to keep the launch branch testable.

Run the **full test suite** after this task (touches `MenuBarController` init
contract and shared construction).

---

## Task 8 — Settings UI: Keep Awake sidebar item + SettingsViewModel extension

**Goal:** the third Settings sidebar item with the duration-cap and
restore-on-launch controls, wired through the existing `SettingsViewModel` and
`SettingsWindowController`.

Observable-contract change: `SettingsSidebarItem` gains `.keepAwake`;
`SettingsViewModel` gains keep-awake draft fields and a `saveKeepAwake(to:)`
method; `SettingsWindowController` holds and saves a `KeepAwakeSettings`. Grep
results (ADR-003 D6):
- `SettingsViewModel.save(to:)` — sole call-site
  `CleanKey/SettingsWindowController.swift:35`. **Do not widen `save(to:)`**; add
  a separate `saveKeepAwake(to: inout KeepAwakeSettings)` so the existing four
  `SettingsViewModelTests` asserting `save(to:)` keep compiling.
- `SettingsSidebarItem` — referenced only in `CleanKey/Views/SettingsView.swift`
  (`allCases`, the `switch selection` in `body`, and `systemImage(for:)`). The
  compiler flags both switches as non-exhaustive — fix both.
- No test references `SettingsSidebarItem` (grep `CleanKeyTests/` empty).

Files to modify:
- `CleanKey/Views/SettingsView.swift` — add `.keepAwake = "Keep Awake"` case;
  add detail branch `case .keepAwake: KeepAwakeSettingsView(viewModel:)`; add
  `systemImage` (`"cup.and.saucer"` or `"sun.max"`).
- `CleanKey/SettingsViewModel.swift` — add `var keepAwakeDurationCap:
  TimeInterval` and `var keepAwakeRestoreOnLaunch: Bool`; init them from an
  injected `KeepAwakeSettings`; add `func saveKeepAwake(to: inout
  KeepAwakeSettings)`. The init gains a second parameter
  `keepAwake: KeepAwakeSettings` (default `KeepAwakeSettings()` to avoid breaking
  any direct construction in tests — grep `SettingsViewModel(` in
  `CleanKeyTests/`: present in `SettingsViewModelTests.swift`; the default keeps
  them compiling).
- `CleanKey/SettingsWindowController.swift` — hold a `var keepAwakeSettings:
  KeepAwakeSettings`; pass it to `SettingsViewModel(settings:keepAwake:)`; in the
  `onSave` closure also call `viewModel.saveKeepAwake(to:
  &self.keepAwakeSettings)`. `AppDelegate` passes the same `KeepAwakeSettings`
  instance it gave the manager — but note `KeepAwakeSettings` is a value type
  backed by `UserDefaults`, so passing separate instances pointing at
  `.standard` is fine (reads/writes go through defaults). Decision: pass a fresh
  `KeepAwakeSettings()` to the window controller (same as `LockSettings` today,
  which is shared by reference of the struct value — both read `.standard`).

Files to create:
- `CleanKey/Views/KeepAwakeSettingsView.swift` — a duration-cap picker
  ("No limit" / 1h / 2h / 4h / 8h / 12h, bound to `keepAwakeDurationCap` via
  `KeepAwakeSettings.allowedCaps`) and a "Re-enable keep-awake when CleanKey
  starts" toggle bound to `keepAwakeRestoreOnLaunch`. View < 150 lines.

Tests to write first (extend `CleanKeyTests/SettingsViewModelTests.swift`):
- `SettingsViewModel(settings:keepAwake:)` reflects the injected
  `KeepAwakeSettings` values.
- `saveKeepAwake(to:)` writes both keep-awake fields and leaves lock fields
  untouched.
- Existing `save(to:)` tests still pass unchanged (lock fields only).
- Cap picker maps "No limit" → `durationCap == 0` and "2h" → `7200` via
  `allowedCaps`.

Run the **full test suite** after this task (shared `SettingsViewModel`).

---

## Task 9 — End-to-end integration pass (hardware)

**Goal:** verify all SPEC-keep-awake §9 success criteria on macOS 14+ hardware.

Manual checklist:
1. Toggle Enable Keep Awake from the menu → `pmset -g assertions` shows both
   `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep`; Disable →
   both gone. (SPEC #1, #7)
2. Icon shows correct state across all four `(isLocked, isAwake)` combinations,
   including lock + keep-awake simultaneously and lock expiring while awake stays
   on. (SPEC #2, #5)
3. With keep-awake active, unplug AC → banner appears within 2 s; tap → disables;
   dismiss → stays on. (SPEC #3, §5.2)
4. Set a 1 h cap (use a short test cap if a debug override exists, else verify
   the timer path by unit test in Task 3) → keep-awake auto-disables at the cap;
   if a lock is also active it continues. (SPEC #4, §7)
5. Enable "Restore on launch", enable keep-awake, quit, relaunch → keep-awake
   re-enables. With it OFF → stays off. (SPEC #6)
6. Quit while active → `pmset -g assertions` clean (no leaked CleanKey
   assertions). (SPEC #7)
7. Deny notification permission → unplug → no banner, no crash. (SPEC §7)
8. No regression: lock, settings, countdown, sound feedback, quick-pick all
   behave as before. (SPEC #8)
9. `codesign --verify --deep --strict CleanKey.app` and
   `spctl --assess --verbose CleanKey.app` pass (entitlements unchanged).

Run the **full test suite** before and after this task. (SPEC #9)

HITL: stop before `git push` and before any GitHub Release.

---

## Risks & HITL gates

- **HITL required:** `git commit`; `git push`; GitHub Release publish;
  `project.pbxproj` edits (build-graph change) reviewed before commit. No file
  deletions are planned in this feature; if one becomes necessary, gate it.
- **Risk — assertion leak on abnormal exit (BRAINSTORM R2):** a force-quit/crash
  could leave the Mac awake. Mitigation: the kernel reaps `IOPMAssertion` on
  process death (so not indefinite), plus `applicationWillTerminate → disable()`.
  Verify in Task 9 step 6 via `pmset -g assertions` after a quit. Add an explicit
  `atexit` release only if a leak is actually observed.
- **Risk — `TestHelpers.swift` is a shared contract:** Tasks 2 and 3 add fakes
  (`FakeSleepAssertionController`, `FakePowerSourceObserver`,
  `FakeBatteryWarningNotifier`). A compile error here blocks every test target.
  Run the full suite immediately after each addition.
- **Risk — power-source callback on the wrong run-loop mode:** if the
  `CFRunLoopSource` is added in `.defaultMode` instead of `.commonModes`, the
  battery callback may not fire while a menu/tracking loop is open. Add in
  `.commonModes`. Verify in Task 9 step 3.
- **Risk — UNUserNotificationCenter authorization timing:** requesting
  authorization inside `enable()` shows the system prompt the first time the user
  enables keep-awake, which may surprise them mid-action. Accepted for v1.1
  (matches Caffeine-class apps). If undesirable, move the request to first launch
  — flagged, not changed now.
- **Risk — restore-on-launch cap semantics:** elapsed cap time is not persisted
  across launches (Task 7), so a restored session restarts the full cap. SPEC §7
  is satisfied (we never restore an "already expired" session because we do not
  track elapsed cap), but the behaviour differs from "resume remaining cap".
  Document in the manifest; persist `capEndsAt` only if a stricter rule is
  requested.
- **Risk — construction order in AppDelegate:** `KeepAwakeManager` must exist
  before `MenuBarController` (which wires `onChange`) and before restore-on-launch
  runs. Wrong order → nil callback or a restore against an unwired icon. Verify
  the order in Task 7.
- **Risk — Swift 6 concurrency at the C callback boundary:** both
  `RealPowerSourceObserver` and `RealSleepAssertionController` cross into C
  callbacks. Reuse the `@unchecked Sendable` context-box discipline from
  `RealEventTapController.TapContext` (single owner, weak back-reference, main-run-
  loop hop). Do not capture `@MainActor` state directly in a C function pointer.
- **Dependency:** Tasks 4 and 5 add the `PowerSourceObserving` and
  `BatteryWarningNotifying` protocols that Task 3's `KeepAwakeManager` already
  references; if executed out of order, stub the protocols in `KeepAwakeProtocols.swift`
  first (declare all three protocols in Task 2/3 so Task 3 compiles, even before
  the real conformers in Tasks 4–5 exist).
- **No entitlement / no Info.plist change** (ADR-003 D4, D5): if any task appears
  to need an entitlement or notification usage key added, stop and escalate —
  the design says none is required.
