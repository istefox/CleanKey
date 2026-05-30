# CleanKey — CLAUDE.md

macOS 14+ menu-bar utility (Swift 6, SwiftUI + AppKit) that locks keyboard and trackpad input via CGEventTap for a user-set duration. MIT license, public GitHub.

## Build & test

```bash
# Build
xcodebuild build -scheme CleanKey -destination 'platform=macOS'

# Test (unit tests only — no UI launch required)
xcodebuild test -scheme CleanKey -destination 'platform=macOS' CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

# Verify signing after build
codesign --verify --deep --strict CleanKey.app
spctl --assess --verbose CleanKey.app
```

## Folder layout

```
CleanKey/
├── CleanKey.xcodeproj
├── CleanKey/                  # app target sources
│   ├── AppDelegate.swift
│   ├── MenuBarController.swift
│   ├── PermissionGuard.swift
│   ├── LockManager.swift      # core — no UI imports
│   ├── LockOverlayController.swift
│   ├── Views/                 # SwiftUI views (TimerPickerView, CountdownView)
│   ├── Info.plist             # LSUIElement = YES
│   └── CleanKey.entitlements
├── CleanKeyTests/             # unit-test target
│   └── ...
├── docs/
│   ├── architecture/ADR-001-cleankey-keyboard-touchpad-lock.md
│   └── superpowers/plans/
├── SPEC.md
├── ARCH.md
└── BRAINSTORM.md
```

## Architecture invariants (ADR-001)

- **LockManager is UI-free.** `startLock(duration:)` and `unlock()` have zero UIKit/AppKit imports. Overlay is injected via `LockPresenting` protocol. Do not add UI calls inside `LockManager`.
- **Teardown order is fixed:** `presenter.dismiss()` → disable tap → remove tap → free context → stop timer. Never change the order; the watchdog depends on it.
- **Wall-clock timekeeping only.** Use `Date()` and `endsAt - Date()` for remaining time. Never count ticks; the countdown must survive sleep/wake.
- **CGEventTap C callback.** Swift state is reached through `UnsafeMutableRawPointer` (`userInfo`). Context is allocated at lock start and freed at unlock. Single owner — do not copy the pointer.

## Gotchas

- `LSUIElement = YES` in `Info.plist` is what hides the Dock icon. Do not set `NSPrincipalClass` to a window controller or the menu bar disappears.
- CGEventTap requires `AXIsProcessTrusted()` to return true at install time. The tap silently fails (returns nil) if the permission is missing — guard before calling `CGEventTapCreate`.
- The watchdog timer runs on the main run loop at 1 s intervals. `CGEventTapIsEnabled` is polled every tick; `AXIsProcessTrusted` every 5th tick. If either returns false, call `unlock()` immediately and post a notification.
- Overlay windows use `.screenSaver` level + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`. The Stage Manager coexistence test on macOS 14 hardware is a named release blocker (see ADR-001 §Risk R2).
- `com.apple.security.device.input-monitoring` is declared in `CleanKey.entitlements` from day one. Do not remove it to simplify signing; it keeps the MAS path open.
- App Sandbox is OFF for the DMG build. Future MAS builds gate sandbox-incompatible calls behind `#if APP_STORE_BUILD`.

## v1.1 extension hooks (no refactor needed)

- **Silent Lock** — inject a no-op `LockPresenting`; `LockManager` already supports it.
- **Global hotkey** — call `LockManager.startLock(duration: lastDuration)` from any hotkey handler; no glue needed.
- **Sound feedback** — `NSSound` at lock/unlock; no architectural change.

## Decisions from chain: Settings and Quick-Pick Lock (ADR-002)

Reference: `docs/architecture/ADR-002-settings-quick-pick.md`

- **`LockPresenting.configure(settings:)` is a no-op default method.** Add new overlay behaviors as defaulted protocol extensions; never as required methods. All existing conformers (`SilentPresenter`, `FakeLockPresenter`) get the default automatically.
- **`EventTapControlling.install(scope:)` is a contract change.** Any future parameter addition requires updating `FakeEventTapController` in `TestHelpers.swift` and running the full suite before merging.
- **`LockSettings.minimumDuration` is 5 s (was 30 s).** Future tests must reference the constant, not the literal `30` or `5`, to survive further range changes.
- **`TwoZoneSlider.swift` is UI-free.** Zone boundary is at step index 12 (60 s → 120 s gap). Both mapping functions (`durationForPosition` / `positionForDuration`) must round-trip all 21 steps — that is the unit-test acceptance bar.
- **`SettingsWindowController` is held strongly by `AppDelegate`.** `showOrFocus()` is the single entry point; `isReleasedWhenClosed = false`. Do not create it as a global singleton or from `MenuBarController`.
- **HUD overlay panels use `.statusBar` window level**, not `.screenSaver`. They must be non-interactive (`ignoresMouseEvents = true`); event blocking happens at the tap layer.
- **Cursor hide/show is scope-gated.** `LockOverlayController.present()` must skip `CGDisplayHideCursor` / `NSCursor.hide()` when `lockScope.trackpadBlocked == false` (i.e. `keyboardOnly` scope). Use a `cursorHidden: Bool` flag and guard in `present()` to avoid double-hide on display hotplug rebuilds.
- **`TimerPickerView` and its tests are retired.** `TimerPickerViewModelTests.swift` must be removed as part of the feature; do not leave orphaned tests for a deleted type.
