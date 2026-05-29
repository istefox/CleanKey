# Plan — CleanKey: Keyboard and Touchpad Lock (TDD)

- **Date:** 2026-05-29
- **Mode:** greenfield
- **SPEC:** /Users/stefanoferri/Developer/Apple/CleanKey/SPEC.md
- **ADR:** /Users/stefanoferri/Developer/Apple/CleanKey/docs/architecture/ADR-001-cleankey-keyboard-touchpad-lock.md
- **ARCH:** /Users/stefanoferri/Developer/Apple/CleanKey/ARCH.md
- **Stack:** Swift 6, macOS 14 Sonoma+, SwiftUI + AppKit, CGEventTap.
- **Test command (provisional):** `xcodebuild test -scheme CleanKey -destination 'platform=macOS'`

## Conventions for the implementer

- Conventional Commits in English. Feature branch only, never commit to `main`.
- HITL gate before: `git commit`, `git push`, any GitHub repo creation, DMG/notarization, permanent deletions. (Auto mode is active for the design phase; these gates still apply to destructive/publishing actions.)
- TDD: for each logic component, write the failing test first, then the minimal
  implementation, then refactor. UI-bound and tap-bound code (event tap install,
  overlay windows, Stage Manager) is verified by integration/manual tests, not unit tests.
- Any helper script must be **Bash 3.2-clean** (macOS default `/bin/bash`): no
  `mapfile`, no `readarray`, no associative arrays, no `${var^^}`, `[[ ]]` ok,
  prefer `printf` over `echo -e`.
- Do not modify `docs/manifests/*.manifest.yml` or `.remember/**` (harness anchors).
- **Greenfield contract note:** no existing call-sites exist, so no stale-contract
  grep is required for v1. Once code lands, any later change to a public signature
  (`startLock(duration:)`, `LockPresenting`, `LockState`) MUST grep the symbol
  across the repo and update tests + call-sites, and run the **full** test suite.

---

## Task 1 — Bootstrap repo, license, ignore, README

**Goal:** a clean, public-ready greenfield repo skeleton (no Xcode project yet).

- `git init` on a feature branch `chore/bootstrap` (do not commit to main).
- Create `LICENSE` — MIT, copyright "2026 Stefano Ferri".
- Create `.gitignore` for Swift/Xcode/macOS (`build/`, `DerivedData/`, `*.xcuserstate`,
  `.DS_Store`, `xcuserdata/`, `*.dmg`). Do NOT ignore `.remember/` if the harness
  needs it tracked — leave `.remember/.gitignore` as-is (anchor).
- Create `README.md`: what CleanKey is, macOS 14+ requirement, install (DMG),
  Accessibility permission note, emergency triple-Escape, build-from-source, MIT badge.
- **Tests:** none (scaffolding). Verify `git status` is clean and files exist.
- **HITL:** stop before the first `git commit` and before any GitHub repo creation.

## Task 2 — Create CleanKey.xcodeproj with app + test targets

**Goal:** buildable menu-bar app shell that launches with no Dock icon and a
unit-test target wired so `xcodebuild test` runs.

- Create `CleanKey.xcodeproj` with:
  - App target `CleanKey` (macOS, deployment target 14.0, Swift 6 language mode).
  - Unit-test target `CleanKeyTests`.
  - Scheme `CleanKey` with the test target attached (so the TEST-CMD works).
- `Info.plist`: `LSUIElement = YES`, bundle id `it.stefer.CleanKey` (or chosen id),
  `NSHumanReadableCopyright`, category Utilities.
- `CleanKey.entitlements`: declare `com.apple.security.device.input-monitoring`.
  App Sandbox OFF for DMG; wrap sandbox-only settings behind `APP_STORE_BUILD` flag.
- Asset catalog with menu-bar template icon placeholder.
- Minimal `CleanKeyApp` / `AppDelegate` that launches and exits cleanly.
- **Test (write first):** a trivial `CleanKeyTests` smoke test (`XCTAssertTrue(true)`)
  to confirm the test target compiles and `xcodebuild test -scheme CleanKey
  -destination 'platform=macOS'` is green. This converts the provisional TEST-CMD
  to brownfield.
- **Verify:** app launches with no Dock icon; test command exits 0.

## Task 3 — LockSettings persistence (UserDefaults)

**Goal:** load/save `lastDuration`, clamped to 30...600, default 120.

- **Test first (`CleanKeyTests/LockSettingsTests`):**
  - default is 120 when nothing stored;
  - value below 30 clamps to 30, above 600 clamps to 600;
  - save then load round-trips a valid value;
  - use an injected `UserDefaults(suiteName:)` so tests do not touch real prefs.
- **Implement:** `LockSettings` with an injected defaults store. Pure logic, no UI.
- **Refactor:** extract clamping into a single function reused by the slider.

## Task 4 — LockManager state machine + escape-combo timing (pure logic)

**Goal:** the testable core of lock/unlock and triple-Escape, with the
event-tap and timer side effects behind injectable seams.

- **Test first (`CleanKeyTests/LockManagerStateTests`):**
  - `startLock(duration:)` from `.idle` → `.locked(endsAt: now+duration, ...)`;
  - remaining-time math uses wall-clock `Date` (advance an injected clock past
    `endsAt` → expiry triggers `unlock()`);
  - escape-combo: 3 Escape keydowns within 1.5 s each → unlock; a 4th-too-late or
    a non-Escape key resets the count (drive the detector function directly with
    `(keyCode, timestamp)` tuples);
  - `unlock()` returns state to `.idle` and invokes teardown exactly once.
- **Implement:** `LockManager` with:
  - injectable `clock: () -> Date`, `tapController: EventTapControlling`,
    `presenter: LockPresenting`, `notifier: Notifying` (all protocols → fakeable);
  - the pure escape-combo evaluator as a free function/struct method so it is
    unit-tested without a real tap;
  - `startLock(duration:)` / `unlock()` with **no UI argument** (ADR Decision 4).
- **Note:** the real `CGEventTap` install lives behind `EventTapControlling`; the
  C-callback wiring is implemented in Task 6, tested via integration.

## Task 5 — LockManager watchdog (1 s poll) over injected seam

**Goal:** detect OS tap disablement and Accessibility revocation while locked and
fail safe.

- **Test first (`CleanKeyTests/WatchdogTests`):** drive the watchdog tick function
  directly (no real `Timer`):
  - tap reports enabled → no action;
  - tap reports disabled → `unlock()` called + notification posted once;
  - on the 5th tick, `AXIsProcessTrusted` fake returns false → same fail-safe path;
  - teardown order asserted: presenter dismissed before tap removed.
- **Implement:** a `watchdogTick(count:)` method on `LockManager` reading
  `tapController.isEnabled` and (every 5th tick) `trustChecker.isTrusted`; wire a
  real 1 s `Timer` only in the non-test path. Inject `trustChecker: TrustChecking`.
- **Refactor:** ensure exactly one timer is started/cancelled per lock (ADR Decision 1).

## Task 6 — Real CGEventTap install + emergency combo wiring (integration)

**Goal:** the production `EventTapControlling` that installs the session tap and
routes the C callback into the tested combo evaluator.

- Implement `RealEventTapController`: `CGEventTapCreate` at `cgSessionEventTap`,
  `headInsertEventTap`, keyboard + pointing-device masks; add run-loop source;
  `CGEventTapEnable`. Allocate the context (`UnsafeMutableRawPointer`) on install,
  free on remove (ADR Decision 6).
- C callback drops all events (returns `nil`) and feeds Escape keydowns to the
  combo evaluator from Task 4 via the context back-reference.
- **Tests:** integration/manual (cannot unit-test a real tap):
  - on a Mac with Accessibility granted, keystrokes are suppressed during lock;
  - triple-Escape unlocks within ~200 ms of the 3rd press;
  - no event leaks after unlock (tap fully removed before next input);
  - revoke Accessibility mid-lock → watchdog restores input + notifies.
- Document the manual steps in `README.md` or a `docs/testing.md`.

## Task 7 — PermissionGuard + first-launch onboarding

**Goal:** gate the app on `AXIsProcessTrusted()` and guide the user to grant it.

- **Test first (`CleanKeyTests/PermissionGuardTests`):** inject a `TrustChecking`
  fake; assert `check()` returns `.granted` / `.missing` correctly and that the
  "open settings" action is invoked only when missing.
- **Implement:** `PermissionGuard` wrapping `AXIsProcessTrusted()`; modal explainer
  + open `System Settings > Privacy > Accessibility`; non-modal notification when
  permission is revoked post-launch (reuse `Notifying` from Task 4).
- **Verify:** first launch with permission missing shows the explainer; granting
  it enables the status item.

## Task 8 — Menu bar (NSStatusItem) + TimerPickerView popover

**Goal:** the user-facing entry to start a lock.

- **Test first:** unit-test the view model backing `TimerPickerView` — slider
  value 30...600, live label formatting ("2 min 30 s"), Start action calls
  `LockManager.startLock(duration:)` with the clamped value and persists it.
- **Implement:** `AppDelegate` creates the `NSStatusItem`; `MenuBarController`
  hosts an `NSPopover` with the SwiftUI `TimerPickerView`; Start closes the popover
  then calls `LockManager.startLock(duration:)`. Close any open popover before
  installing the tap (lock is not re-entrant — SPEC edge case).
- **Verify:** popover opens from the menu bar, slider persists, Start locks.

## Task 9 — LockOverlayController (optional presenter) + CountdownView

**Goal:** the fullscreen overlay per display, injected as `LockPresenting`.

- Implement `LockOverlayController : LockPresenting`:
  - one borderless `NSWindow` per `NSScreen`, `level = .screenSaver`,
    `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
    .ignoresCycle]`, black 0.95, `ignoresMouseEvents = true`, not key/main;
  - SwiftUI `CountdownView` (remaining time + "Hold Esc x3 to unlock"), 1 s refresh;
  - rebuild on `NSApplicationDidChangeScreenParameters` while locked.
- Inject it into `LockManager`; the no-op presenter (Silent Lock) is a separate
  type selectable later (ADR Decision 3) — leave the seam, do not build the toggle.
- **Tests:** integration/manual — overlay covers all displays incl. external;
  hotplug rebuilds; countdown accurate within ±1 s over 10 min.
- **Named acceptance test (ADR Decision 2):** on macOS 14 with **Stage Manager
  enabled**, the overlay covers all displays, is not repositioned/grouped, and is
  dismissed cleanly on unlock. Record the result before tagging v1.

## Task 10 — End-to-end integration pass + distribution prep

**Goal:** prove the full flow and prepare notarized distribution.

- Integration checklist run on hardware: normal lock→expiry; triple-Escape unlock;
  watchdog-disable path; Accessibility-revoke path; multi-display + hotplug;
  sleep/wake during lock; idle ≤ 5 MB / locked ≤ 10 MB RAM (SPEC success criteria).
- Build a signed Release, archive, notarize, staple; verify `codesign --verify`
  and `spctl --assess`. Produce the DMG.
- Update `README.md` with the verified install + permission instructions.
- **HITL:** stop before notarization upload, before `git push`, before publishing
  the GitHub Release, and before making the repo public.

---

## Risks & HITL gates (summary)

- **HITL required:** first `git commit`; `git push`; GitHub repo creation /
  making it public; notarization upload; DMG/Release publish; any permanent deletion.
- **Risk — watchdog timing:** if the 1 s poll lags, a stale overlay could sit over
  live input. Keep the watchdog on the main run loop; assert teardown order in tests.
- **Risk — Stage Manager:** window-level coexistence cannot be unit-tested; Task 9
  named hardware test is a release blocker.
- **Risk — C-callback memory:** the tap context is manually allocated/freed;
  double-free or leak if lock/unlock ordering breaks. Allocate on install, free on
  remove, single owner (`RealEventTapController`).
- **Dependency:** Apple Developer ID for signing/notarization (DMG) and the
  input-monitoring entitlement provisioning for a future MAS submission.
