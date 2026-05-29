# SPEC — CleanKey: Keyboard and Touchpad Lock for Cleaning

## Objective

CleanKey is a macOS menu-bar utility that temporarily locks all keyboard and trackpad input so the user can safely clean the hardware. The user sets a duration, activates the lock, and all input is suppressed until the timer expires or an emergency combo is held.

## Scope

**In scope:**
- Menu bar app (no Dock icon) for macOS 14 Sonoma+
- Input blocking via CGEventTap (keyboard + trackpad/pointing devices)
- Fullscreen dark overlay covering every connected display with a live countdown
- Duration picker via slider in a menu bar popover (30 s – 10 min)
- Emergency unlock via triple-Escape held within a 2-second window
- First-launch Accessibility permission onboarding
- Persistent last-used duration (UserDefaults)
- MIT-licensed open source, distributed via GitHub Releases (notarized DMG); entitlements planned to keep Mac App Store path open

**Out of scope (v1):**
- System-wide audio blocking
- Scheduled/calendar-based locking
- Password-protected unlock
- iOS / iPadOS companion

## Stack

| Layer | Technology |
|---|---|
| Language | Swift 6 |
| UI framework | SwiftUI + AppKit bridge (NSStatusItem, NSWindow) |
| Input blocking | CGEventTap (CoreGraphics) |
| Persistence | UserDefaults |
| Minimum OS | macOS 14 Sonoma |
| Distribution | Notarized DMG (primary); MAS-compatible entitlements from day one |
| License | MIT |

## Architecture

```
CleanKey.app
├── AppDelegate           — NSStatusItem ownership, app lifecycle, no Dock icon
├── MenuBarController     — NSPopover with SwiftUI TimerPickerView
├── LockManager           — CGEventTap lifecycle, timer state machine
├── LockOverlayController — creates/destroys one NSWindow per NSScreen
└── PermissionGuard       — AXIsProcessTrusted check, opens System Settings if needed
```

**Input blocking:**
`LockManager` installs a `CGEventTap` at `CGEventTapLocation.cgSessionEventTap` at the highest insertion point, listening on all keyboard and pointing-device event types. The callback returns `nil` (drops the event) for the entire lock duration except for the emergency combo detection.

**Emergency unlock (triple Escape):**
The CGEventTap callback tracks consecutive `keyDown` events with `keyCode == 53` (Escape). Three consecutive Escape presses with an inter-press interval ≤ 1.5 s trigger `LockManager.unlock()`. The count resets on any non-Escape keydown or on timeout.

**Overlay windows:**
On lock start, `LockOverlayController` creates one `NSWindow` per `NSScreen.screens` entry:
- Style: `borderless`, `NSWindowCollectionBehavior.canJoinAllSpaces + .fullScreenAuxiliary`
- Level: `NSWindow.Level.screenSaver` (above everything)
- Background: black at 0.95 opacity
- Content: SwiftUI `CountdownView` showing remaining time in large digits plus a dim hint line "Hold Esc × 3 to unlock"
- Not key/main window; ignores mouse/trackpad events through the window itself (input blocking is at the CGEventTap layer, not the window layer)

On display configuration changes (NSApplicationDidChangeScreenParametersNotification) while locked, the overlay rebuilds to match new screen set.

## Data Model

```swift
// Persisted in UserDefaults
struct LockSettings {
    var lastDuration: TimeInterval   // seconds, range 30–600, default 120
}

// In-memory only
enum LockState {
    case idle
    case locked(endsAt: Date, escapeCount: Int, lastEscapeAt: Date?)
}
```

## UI Flows

### First launch
1. App starts → `PermissionGuard.check()`.
2. If `AXIsProcessTrusted() == false`: show a modal alert explaining the requirement → open `System Settings > Privacy > Accessibility`. App is not usable until permission is granted.
3. If granted: menu bar icon appears, popover ready.

### Normal lock flow
1. User clicks menu bar icon → popover opens with `TimerPickerView`.
2. Slider shows current `lastDuration` (default 120 s). User drags to desired value; label updates live ("2 min 30 s").
3. User clicks **Start Lock** button.
4. Popover closes. `LockManager.startLock(duration:)` is called.
5. CGEventTap installed. One overlay window created per screen at `NSWindow.Level.screenSaver`.
6. `CountdownView` updates every second via a `Timer` or `AsyncStream<Void>`.
7. Timer expires → `LockManager.unlock()` called automatically.
8. Overlay windows closed. CGEventTap removed. Menu bar icon returns to idle state.

### Emergency unlock
1. While locked, user holds Escape three times within 1.5 s.
2. `LockManager.unlock()` called on the third detection.
3. Same cleanup as normal expiry.

### Accessibility permission missing (post-first-launch)
If the permission is revoked while the app is running, the CGEventTap fails to install. Show a non-modal notification via `NSUserNotification` / `UNUserNotificationCenter`: "CleanKey cannot block input — Accessibility access was revoked." Do not start the lock.

## Edge Cases

| Scenario | Handling |
|---|---|
| Display connected/disconnected while locked | Rebuild overlay windows on `NSApplicationDidChangeScreenParametersNotification` |
| Sleep/wake while locked | Lock continues; timer counts wall-clock time via `Date` comparison, not tick count |
| Fast user switching | CGEventTap is session-scoped; other sessions unaffected |
| App crash while locked | CGEventTap is automatically removed by the OS when the process exits; user regains input immediately |
| CGEventTap disabled by OS (watchdog) | Detect `CGEventTapIsEnabled` returning false on a 1 s poll; show alert and restore normal input |
| MAS sandbox path | Entitlement `com.apple.security.device.input-monitoring` declared in `.entitlements`; sandbox-incompatible APIs (if any) wrapped behind a compile-time flag `APP_STORE_BUILD` |
| Duration slider at minimum (30 s) | Valid; countdown starts, emergency combo still available |
| Lock started with Accessibility popover open | Close popover before installing tap; lock is not re-entrant |

## Success Criteria

1. On a Mac with Accessibility permission granted, all keyboard and trackpad events are suppressed for the configured duration.
2. Triple-Escape combo reliably unlocks within 200 ms of the third press.
3. The overlay covers all connected displays including external monitors.
4. The countdown is accurate within ±1 second over a 10-minute lock.
5. The app uses ≤ 5 MB RAM at idle and ≤ 10 MB while locked.
6. The app passes `codesign --verify` and `spctl --assess` (notarization).
7. No event is dropped after unlock (CGEventTap is fully removed before the OS processes the next input).
8. First-launch Accessibility onboarding leads the user to grant permission in System Settings without error.
