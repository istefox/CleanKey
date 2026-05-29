# ARCH — CleanKey

Global architecture for the CleanKey macOS menu-bar utility. This document is the
durable reference for how the system is structured; per-decision rationale lives
in `docs/architecture/ADR-001-cleankey-keyboard-touchpad-lock.md`.

## 1. Purpose

CleanKey temporarily suppresses all keyboard and trackpad input for a fixed
duration so the user can clean the hardware, then restores input without a
password prompt. Menu-bar only, macOS 14 Sonoma+, Swift 6.

## 2. Runtime shape

- App bundle: `CleanKey.app`, `LSUIElement = YES` (no Dock icon, no main window).
- Single process, single session-scoped `CGEventTap`.
- No network, no accounts, no analytics. Only persisted state is `lastDuration`
  in `UserDefaults`.

## 3. Component map

```
CleanKey.app  (LSUIElement, menu-bar only)
│
├── AppDelegate
│     owns NSStatusItem · app lifecycle · hides Dock icon
│     holds PermissionGuard, LockManager, MenuBarController
│
├── PermissionGuard
│     AXIsProcessTrusted() · first-launch onboarding
│     opens System Settings > Privacy > Accessibility
│
├── MenuBarController
│     NSPopover hosting SwiftUI TimerPickerView
│     reads/writes lastDuration (UserDefaults)
│     calls LockManager.startLock(duration:)
│
├── LockManager                      ← core, only owner of the tap + timer
│     CGEventTap lifecycle (cgSessionEventTap, highest insertion)
│     wall-clock timer state machine (LockState)
│     watchdog (1s Timer: CGEventTapIsEnabled; AXIsProcessTrusted every 5s)
│     emergency triple-Escape detection (inside C callback)
│     public entry: startLock(duration:) / unlock()  — NO UI dependency
│     emits state via LockPresenting protocol + state callback/AsyncStream
│
└── LockOverlayController : LockPresenting   ← OPTIONAL (injected)
      one NSWindow per NSScreen at .screenSaver level
      SwiftUI CountdownView (remaining time + "Hold Esc x3 to unlock")
      rebuilds on NSApplicationDidChangeScreenParameters while locked
```

## 4. Key data types

```swift
struct LockSettings {            // persisted in UserDefaults
    var lastDuration: TimeInterval   // 30...600, default 120
}

enum LockState {                 // in-memory only
    case idle
    case locked(endsAt: Date, escapeCount: Int, lastEscapeAt: Date?)
}

protocol LockPresenting {        // decouples overlay from LockManager
    func present(state: LockState)
    func dismiss()
}
```

`endsAt` is an absolute `Date`; remaining time is `endsAt - Date()`. This keeps
the countdown correct across sleep/wake (wall-clock, not tick count).

## 5. Control flow

### First launch
AppDelegate → PermissionGuard.check(). If not trusted: modal explainer → open
System Settings. App is unusable until granted. If trusted: status item appears.

### Lock
Popover → Start Lock → `LockManager.startLock(duration:)`:
1. Persist `lastDuration`.
2. Allocate the tap context (holds escape-combo state + back-reference).
3. Install `CGEventTap` at `cgSessionEventTap`, highest insertion, listening on
   keyboard + pointing-device event types; enable it.
4. Call `presenter.present(state:)` → overlay windows created (or no-op for
   Silent Lock).
5. Start the 1 s watchdog/countdown `Timer`.

### Unlock (timer expiry OR triple-Escape OR watchdog failure)
`LockManager.unlock()`, deterministic teardown order every time:
1. `presenter.dismiss()` (overlay windows closed) — visual first.
2. Disable + remove the `CGEventTap`; remove run-loop source.
3. Free the tap context allocation.
4. Stop the timer; set state `.idle`.
5. On watchdog failure only: post a user notification.

### Display hotplug while locked
`NSApplicationDidChangeScreenParameters` → presenter rebuilds windows to match
`NSScreen.screens`. LockManager state is untouched.

## 6. Input-blocking contract

- Tap location: `CGEventTapLocation.cgSessionEventTap`, placement
  `headInsertEventTap`, option `defaultTap` (active, can drop events).
- Callback returns `nil` to drop every event during `locked`, except it inspects
  Escape keydowns for the emergency combo and (on the 3rd) triggers unlock.
- The callback is a C function pointer; Swift state is reached through
  `UnsafeMutableRawPointer` (`userInfo`) → context struct allocated at lock start,
  freed at unlock.
- Overlay windows set `ignoresMouseEvents = true` so blocking stays solely at the
  tap layer (the tap must still see events to detect the combo).

## 7. Failure modes and safety

| Failure | Handling |
|---|---|
| OS disables the tap | 1 s watchdog `CGEventTapIsEnabled` → unlock + notify |
| Accessibility revoked while locked | 5 s `AXIsProcessTrusted` check → unlock + notify |
| Accessibility revoked before lock | tap install fails → do not start, notify |
| App crash while locked | OS auto-removes the tap; input restored immediately |
| Sleep/wake | wall-clock `Date` math; countdown stays correct |
| Display add/remove | overlay rebuild on screen-params notification |
| Stage Manager / full-screen app | `.screenSaver` level + `.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle`; validated by named hardware test |

## 8. Extension hooks (v1.1, no refactor required)

- **Silent Lock** — inject a no-op `LockPresenting`; toggle in the popover.
- **Global hotkey** — register a hotkey that calls
  `LockManager.startLock(duration: lastDuration)` directly (entry point is
  UI-free by design).
- **Sound feedback** — `NSSound` on lock/unlock; zero architectural impact.

## 9. Build, signing, distribution

- `CleanKey.xcodeproj` with an app target (bundle, `Info.plist`, asset catalog,
  `CleanKey.entitlements`) and a unit-test target compiling the core logic files.
- `CleanKey.entitlements` declares `com.apple.security.device.input-monitoring`
  from day one (keeps MAS path open). App Sandbox off for DMG; gated behind
  `APP_STORE_BUILD` for a future MAS build.
- Primary distribution: notarized DMG via GitHub Releases. Must pass
  `codesign --verify` and `spctl --assess`.
- License: MIT. Public GitHub repository.

## 10. Testability boundary

Core logic (`LockManager` state machine, escape-combo timing math,
`PermissionGuard` trust gating, `LockSettings` persistence) lives in files
compiled into a unit-test target and is tested without launching the UI. The
event-tap installation, overlay window creation, and Stage Manager coexistence
are validated by manual/integration tests on hardware — they cannot be asserted
in pure unit tests.
