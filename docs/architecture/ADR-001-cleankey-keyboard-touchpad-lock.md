# ADR-001 — CleanKey: Keyboard and Touchpad Lock for Cleaning

## Status

Accepted — 2026-05-29

## Context

CleanKey is a greenfield macOS 14 (Sonoma)+ menu-bar utility. Its single
responsibility is to suppress all keyboard and trackpad input for a precisely
known duration so the user can clean the hardware, then restore input without
forcing re-authentication.

The irreducible technical constraint, established in BRAINSTORM.md, is that
macOS routes all HID events through the kernel and the session event stream.
Suppression therefore has to happen at the session event-tap level
(`CGEventTap` at `cgSessionEventTap`) or lower. The product constraint is that
the user must regain full control in finite time with no password prompt, which
rules out delegating to the system lock screen.

Several decisions have long-term cost if made wrong now:

1. The event tap can be silently disabled by the OS while the visual overlay is
   still on screen, producing a dangerous state where the user believes input is
   blocked but it is not. A health watchdog is load-bearing, not optional.
2. The fullscreen overlay window level must coexist with Stage Manager and
   native full-screen apps on macOS 14. Picking the wrong window level or
   collection behavior risks display glitches or undismissable windows.
3. Two near-term v1.1 features (Silent Lock without overlay; global hotkey to
   start the lock) must not require refactoring. The overlay must be optional and
   the lock entry point must be UI-free.
4. Mac App Store distribution must remain possible without a future signing
   rebuild, which means the input-monitoring entitlement must be declared from
   day one even though v1 ships as a notarized DMG.

This ADR records the architecture for v1 and the hooks that keep v1.1 cheap.

## Decision

Adopt **Alternative A (Full Lock)** from BRAINSTORM.md as the v1 architecture:
`CGEventTap` input suppression plus a fullscreen dark overlay per display, with
triple-Escape and timer expiry as the two unlock paths.

The application is a menu-bar-only app (`LSUIElement = YES`, no Dock icon),
built in Swift 6 with a SwiftUI + AppKit hybrid. Component responsibilities:

- **AppDelegate** — owns the `NSStatusItem`, app lifecycle, and the
  `PermissionGuard`. Hides the Dock icon. No business logic.
- **PermissionGuard** — wraps `AXIsProcessTrusted()`; runs the first-launch
  onboarding and opens System Settings → Privacy → Accessibility when access is
  missing. Pure, UI-thin, independently testable.
- **LockManager** — the core. Owns the `CGEventTap` lifecycle, the wall-clock
  timer state machine, the watchdog, and the emergency-combo detection. Its
  public entry point is `startLock(duration:)` with **no UI dependency**. It
  exposes lock-state changes through a callback/`AsyncStream` that the UI
  observes; the overlay is a *consumer*, never a hard dependency.
- **LockOverlayController** — creates and tears down one `NSWindow` per
  `NSScreen`. It is **optional**: `LockManager` references it through a protocol
  (`LockPresenting`) and a nil/no-op implementation produces Silent Lock with no
  code change to `LockManager`.
- **MenuBarController / TimerPickerView** — the SwiftUI popover with the duration
  slider; calls `LockManager.startLock(duration:)` and persists `lastDuration`
  to `UserDefaults`.

### Decision 1 — Watchdog poll strategy

`LockManager` runs a single repeating `Timer` (1 s interval, main run loop)
while in the `locked` state. Each tick:

- calls `CGEventTapIsEnabled(tap)`. If it returns `false`, the OS has disabled
  the tap: immediately `unlock()` (tear down overlay, remove the tap reference)
  and post a user notification "Lock ended early — Accessibility tap was
  disabled by macOS".
- every 5th tick (i.e. every 5 s) also calls `AXIsProcessTrusted()`. If it
  returns `false`, treat it identically to a disabled tap.

Rationale for a single 1 s timer rather than two timers: one timer is simpler to
reason about and to cancel atomically on unlock; the 5 s Accessibility check is
derived from a tick counter, so there is exactly one timer to start and stop.
The watchdog must fire its teardown *before* the user can act on the false
"locked" signal, hence the 1 s cadence (the SPEC's success criterion is
restoration within ~1 s of OS disablement).

### Decision 2 — Overlay window level for fullscreen + Stage Manager

Each overlay `NSWindow` uses:

- `styleMask = .borderless`, not key, not main, `ignoresMouseEvents = true`
  (blocking is at the tap layer, the window must not also swallow events that the
  tap needs to evaluate for the emergency combo).
- `level = .screenSaver` (`CGShieldingWindowLevel()`-class, above normal app and
  menu-bar windows).
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
  .stationary, .ignoresCycle]`. `.canJoinAllSpaces` + `.fullScreenAuxiliary`
  lets the overlay sit over native full-screen Spaces; `.stationary` prevents
  Stage Manager and Mission Control from repositioning or grouping it;
  `.ignoresCycle` keeps it out of window cycling.
- one window per `NSScreen.screens`, each sized to its screen `frame`.

Stage Manager coexistence on macOS 14 is treated as an **explicit acceptance
criterion with a named test** (see Consequences and the plan), not an
assumption: the combination above is the design intent, validated on hardware
before v1 ships.

### Decision 3 — Optional overlay (Silent Lock hook)

`LockManager` depends on a `LockPresenting` protocol
(`present(state:)` / `dismiss()`), not on `LockOverlayController` concretely.
v1 injects `LockOverlayController`; v1.1 Silent Lock injects a no-op presenter
selected by a popover toggle. No `LockManager` change required.

### Decision 4 — UI-free lock entry point (global hotkey hook)

`LockManager.startLock(duration:)` and `unlock()` take no view, window, or popover
arguments and perform no UI work directly. The future global hotkey
(`NSEvent.addGlobalMonitorForEvents` or a Carbon `RegisterEventHotKey`
registration) calls `startLock(duration:lastDuration)` directly.

### Decision 5 — MAS entitlements from day one

`CleanKey.entitlements` declares `com.apple.security.device.input-monitoring`
from the first commit. The DMG build is the primary v1 target, but the
entitlement and an `APP_STORE_BUILD` compile-time flag (wrapping any
sandbox-incompatible API, if discovered) keep the MAS path open without a future
signing rebuild. App Sandbox is left off for the DMG build and gated behind
`APP_STORE_BUILD` for a future MAS build.

### Decision 6 — Emergency unlock (triple-Escape) inside the tap callback

Detection lives **inside** the `CGEventTap` C callback, not in a separate
monitor, because the callback is the only place guaranteed to see events while
all input is being dropped. The callback tracks consecutive `keyDown` with
`keyCode == 53` (Escape); three within an inter-press interval ≤ 1.5 s call
`unlock()`. Any non-Escape keydown or a timeout resets the count. State is held
in a context struct passed via the tap's `userInfo` pointer (the callback is a
C function pointer and cannot capture Swift context directly).

## Alternatives considered

### Alternative A — Full Lock (ADOPTED)

CGEventTap suppression + fullscreen dark overlay per display + live countdown +
triple-Escape unlock. **Adopted** because it is the only approach that satisfies
every stated differentiation goal simultaneously: complete keyboard + trackpad
suppression, an unambiguous "do not touch" visual signal across all displays,
accurate countdown, and a notarized modern distribution. The two known risks
(watchdog invalidation, Stage Manager window level) are addressed directly in
this ADR rather than deferred.

### Alternative B — Silent Lock, no overlay (REJECTED for v1, retained as v1.1 hook)

Same CGEventTap suppression but no fullscreen overlay; lock state shown only as a
menu-bar countdown badge. **Rejected for v1** because the "locked" signal is too
weak: a returning user or a bystander may not realise the Mac is still locked,
and there is no visual deterrent — which undercuts the core cleaning use case
where the screen is the primary "locked" cue. **Retained architecturally**: the
optional `LockPresenting` injection (Decision 3) makes Silent Lock a v1.1 toggle,
not a rewrite. This is the deliberate reason the overlay is decoupled.

### Alternative C — System Lock Bridge (REJECTED)

Delegate blocking to the macOS system screen lock (`CGSession` lock) on a timer,
auto-unlocking on expiry; requires no Accessibility permission. **Rejected**: the
system lock screen forces password re-authentication on return. A 2-minute
cleaning session must not require typing a password afterward — that defeats the
product's entire reason to exist. The zero-permission upside does not compensate
for breaking the primary flow.

### Alternative (tooling) — Swift Package vs Xcode project (REJECTED: SPM-only)

A pure Swift Package Manager executable was considered to avoid the `.xcodeproj`.
**Rejected** for the app target: a notarized, code-signed, menu-bar `.app`
bundle with `Info.plist` (`LSUIElement`), an `.entitlements` file, and an asset
catalog is materially simpler to build, sign, and notarize through an
`.xcodeproj` app target than through SPM bundle plumbing on macOS 14. Decision:
ship `CleanKey.xcodeproj` with an app target for the bundle, and keep core
logic (`LockManager`, `PermissionGuard`, state types) in files that a separate
unit-test target compiles, so logic remains testable without launching the UI.

## Consequences

### Positive

- Single, well-bounded responsibility per component; `LockManager` is the only
  component touching the event tap and the timer, making the dangerous code path
  small and auditable.
- The watchdog (Decision 1) closes the most dangerous failure mode — a stale
  overlay over live input — within ~1 s, satisfying the SPEC safety criterion.
- v1.1 Silent Lock and global hotkey cost roughly one injection and one
  registration call respectively, because the overlay is optional (Decision 3)
  and the lock entry point is UI-free (Decision 4).
- MAS entitlement from day one (Decision 5) means the App Store path never
  requires re-signing the binary against a changed entitlement set.
- Crash safety is free: the OS removes a process's event tap on exit, so a crash
  while locked restores input immediately (SPEC edge case).
- Wall-clock timing (`Date` comparison, not tick counting) makes the countdown
  correct across sleep/wake.

### Negative

- Two subsystems (event tap + overlay windows) must be coordinated, especially on
  display hotplug and on watchdog teardown; the unlock path must tear both down
  in a deterministic order (overlay first, then tap reference) every time.
- Stage Manager coexistence cannot be fully proven by unit tests; it needs a
  manual hardware acceptance test on macOS 14 with Stage Manager enabled, which
  is a recurring cost on each macOS major release.
- The triple-Escape detector lives in a C callback with state behind an
  `UnsafeMutableRawPointer`; this is the least Swift-idiomatic part of the
  codebase and needs careful memory-ownership discipline (context allocated on
  lock start, freed on unlock).
- Disabling App Sandbox for the DMG build means the MAS build path is not
  exercised continuously; `APP_STORE_BUILD` differences can rot if not built
  periodically.

### Neutral

- UserDefaults is the persistence layer; only `lastDuration` is stored, so no
  migration strategy is needed now.
- The app has no network, no analytics, no accounts — the threat surface is
  limited to the input-monitoring entitlement itself.
- The countdown view refreshes once per second; sub-second precision is not a
  requirement.

## References

- /Users/stefanoferri/Developer/Apple/CleanKey/SPEC.md
- /Users/stefanoferri/Developer/Apple/CleanKey/BRAINSTORM.md
- /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md
- Apple: Quartz Event Services (`CGEventTapCreate`, `CGEventTapIsEnabled`,
  `CGEventTapEnable`)
- Apple: `AXIsProcessTrusted` / `AXIsProcessTrustedWithOptions`
- Apple: `NSWindow.Level`, `NSWindow.CollectionBehavior`, `CGShieldingWindowLevel()`
