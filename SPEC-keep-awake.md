# SPEC — Keep-Awake Feature Addition to CleanKey

**Version:** 1.0  
**Date:** 2026-05-31  
**Scope:** Additive feature on top of CleanKey v1.1 (input-lock, settings, menu bar)

---

## 1. Objective

Add Caffeine/Amphetamine-style keep-awake functionality to CleanKey so that a single
menu-bar agent covers both input locking and sleep prevention. The two features are
independent, coexist freely, and share the same status item and settings window.

---

## 2. Scope

**In scope:**
- Keep-awake toggle (indefinite by default, optional duration cap 1 h–12 h in Settings)
- Prevents both display sleep and system sleep via two `IOPMAssertion` calls
- Single menu-bar icon that reflects the combined app state (idle / lock / awake / both)
- Battery-unplug warning notification when keep-awake is active
- New "Keep Awake" sidebar section in the existing Settings window
- "Restore keep-awake on launch" opt-in checkbox (default: OFF)
- `UserDefaults` persistence for keep-awake settings

**Out of scope:**
- Screensaver prevention (not requested)
- Per-app keep-awake rules
- Scheduled keep-awake (time of day triggers)
- Lid-close behavior override
- Any change to the existing lock feature logic

---

## 3. Stack

Inherits the CleanKey stack without change:

- **Language:** Swift 6 (strict concurrency)
- **UI:** SwiftUI + AppKit, `@Observable` view models
- **Target:** macOS 14+
- **Sleep API:** `IOKit` — `IOPMAssertionCreateWithName` / `IOPMAssertionRelease`
- **Power source monitoring:** `IOPSNotificationCreateRunLoopSource` (unplugged detection)
- **Settings persistence:** `UserDefaults`
- **Notifications:** `NSUserNotificationCenter` / `UNUserNotificationCenter` (for battery warn)

---

## 4. Architecture

### 4.1 KeepAwakeManager

New type, parallel to `LockManager`. UI-free (`@MainActor`). Responsibilities:

- Holds two `IOPMAssertionID` values (display-sleep + system-sleep assertions)
- Exposes `isActive: Bool` (computed from assertion IDs)
- `enable()` — creates both assertions; starts power-source observer; starts optional cap timer
- `disable()` — releases both assertions; tears down observer and timer
- Cap timer: fires after user-configured max duration → calls `disable()` automatically
- Power-source callback: if `isActive && batteryNowUnplugged` → post notification (does NOT auto-disable)

### 4.2 AppState (new lightweight observable)

Bridges `LockManager` and `KeepAwakeManager` state into one observable for the menu bar icon:

```
enum AppDisplayState {
    case idle
    case keepAwakeOnly
    case lockedOnly
    case lockedAndKeepAwake
}
```

`MenuBarController` observes `AppDisplayState` to pick the correct `NSImage`.

### 4.3 MenuBarController changes

- New menu items: **"Enable Keep Awake"** / **"Disable Keep Awake"** (toggled dynamically)
- Icon switches to a combined-state image set (four variants — see §6)
- Delegates enable/disable to `KeepAwakeManager`

### 4.4 Settings

New `KeepAwakeSettingsView` added as a third sidebar item ("Keep Awake") in `SettingsView`.

New `KeepAwakeSettings` struct (mirrors `LockSettings` pattern):
- `durationCap: TimeInterval?` — nil = indefinite; non-nil = 1 h–12 h
- `restoreOnLaunch: Bool` — default `false`

`SettingsViewModel` gains `keepAwakedurationCap` and `keepAwakeRestoreOnLaunch` bindable properties.

### 4.5 AppDelegate changes

- Instantiates `KeepAwakeManager` alongside `LockManager`
- On launch: if `restoreOnLaunch == true && lastKeepAwakeState == true` → calls `keepAwakeManager.enable()`

---

## 5. UI Flows

### 5.1 Toggle keep-awake via menu

1. User clicks status item → menu appears
2. Menu shows "Enable Keep Awake" (when off) or "Disable Keep Awake" (when on)
3. Click → `KeepAwakeManager.enable()` or `disable()`
4. Status icon updates immediately to reflect new combined state
5. If duration cap is set, a countdown is NOT shown in the title (unlike lock mode) — cap is silent

### 5.2 Battery unplug warning

1. Keep-awake is active; user unplugs power adapter
2. `IOPSNotificationCreateRunLoopSource` callback fires
3. App posts a `UNUserNotificationCenter` banner: "Keep Awake is active on battery — tap to disable"
4. Tapping the notification calls `disable()`; dismissing does nothing (keep-awake stays on)

### 5.3 Lock + Keep Awake simultaneously

1. Keep-awake is ON (icon: sun)
2. User starts a lock from the menu
3. Icon switches to combined state (padlock + sun)
4. Both `LockManager` and `KeepAwakeManager` run independently
5. Lock expires → icon returns to sun only; keep-awake remains active

### 5.4 Keep Awake Settings

Path: Status item → Settings → "Keep Awake" sidebar item

Controls:
- **Duration cap** — toggle + stepper/picker: "No limit" (default) or 1 h / 2 h / 4 h / 8 h / 12 h
- **Restore on launch** — Toggle: "Re-enable keep-awake when CleanKey starts" (default: OFF)

Changes are written to `UserDefaults` on Save.

---

## 6. Icon State Set (4 variants)

| State | Symbol description |
|---|---|
| `idle` | CleanKey logo (padlock, unlocked) |
| `keepAwakeOnly` | Sun / coffee-cup symbol |
| `lockedOnly` | Closed padlock |
| `lockedAndKeepAwake` | Closed padlock + sun badge |

All variants: template image, 18×18 pt, supports light/dark menu bar.

---

## 7. Edge Cases

| Case | Behaviour |
|---|---|
| App quits while keep-awake active | `KeepAwakeManager.disable()` called in `applicationWillTerminate`; assertions released |
| Sleep triggered externally (lid close, `pmset sleepnow`) | IOPMAssertion cannot override lid-close sleep; keep-awake is silently bypassed — no special handling needed |
| Duration cap expires while lock is also active | Cap fires → `disable()` runs; lock continues unaffected |
| `IOPMAssertionCreate` fails (rare, entitlement/sandbox issue) | Log error via `Logger`; set `isActive = false`; show notification "Keep Awake unavailable" |
| Notification permission denied | Battery warning silently skipped; no crash |
| `restoreOnLaunch = true` but cap already expired at restore time | Restore is skipped (cap has elapsed); keep-awake stays OFF |

---

## 8. Persistence

| Key | Type | Default |
|---|---|---|
| `keepAwakeDurationCap` | `Double` (seconds, 0 = no cap) | `0` |
| `keepAwakeRestoreOnLaunch` | `Bool` | `false` |
| `keepAwakeLastActiveState` | `Bool` | `false` — written on disable/enable |

---

## 9. Success Criteria

- [ ] Keep-awake toggle activates/deactivates both display and system sleep assertions
- [ ] Menu bar icon shows correct combined state across all four `AppDisplayState` values
- [ ] Battery unplug notification fires within 2 s of unplugging (when keep-awake is active)
- [ ] Duration cap (when set) auto-disables keep-awake after the configured time
- [ ] Lock and keep-awake can both be active simultaneously without interfering
- [ ] "Restore on launch" setting correctly re-enables keep-awake on next app start
- [ ] All assertions released cleanly on app quit (verified via `pmset -g assertions`)
- [ ] No regression in existing lock, settings, countdown, or sound-feedback features
- [ ] All existing tests remain green; new unit tests cover `KeepAwakeManager` state transitions
