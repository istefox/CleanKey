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
| App crash while locked | The OS automatically removes the CGEventTap when the process exits; the user regains input immediately |
| CGEventTap disabled by OS (watchdog) | Detect `CGEventTapIsEnabled` returning false on a 1 s poll; show alert and restore normal input |
| MAS sandbox path | Entitlement `com.apple.security.device.input-monitoring` declared in `.entitlements`; sandbox-incompatible APIs (if any) wrapped behind a compile-time flag `APP_STORE_BUILD` |
| Duration slider at minimum (30 s) | Valid; countdown starts, emergency combo still available |
| Lock started with Accessibility popover open | Close popover before installing tap; lock is not re-entrant |

## Success Criteria

1. On a Mac with Accessibility permission granted, CleanKey suppresses all keyboard and trackpad events for the configured duration.
2. Triple-Escape combo reliably unlocks within 200 ms of the third press.
3. The overlay covers all connected displays including external monitors.
4. The countdown is accurate within ±1 second over a 10-minute lock.
5. The app uses ≤ 5 MB RAM at idle and ≤ 10 MB while locked.
6. The app passes `codesign --verify` and `spctl --assess` (notarization).
7. The app drops no events after unlock (the CGEventTap is fully removed before the OS processes the next input).
8. First-launch Accessibility onboarding leads the user to grant permission in System Settings without error.

---

## Feature: Settings and Quick-Pick Lock

### Objective

Extend CleanKey with a persistent settings panel and a redesigned lock-entry flow. Users configure a default lock duration, overlay mode, and trackpad behavior once in Settings; when they trigger a lock, a quick-pick menu shows four fixed presets plus their personal default so they can start a lock in one click.

### Scope

**In scope:**
- Replace the slider popover (left-click) with a native `NSMenu` showing time presets.
- Right-click the menu bar icon → contextual menu with **Settings…** and **Quit**.
- Settings window: standard macOS Settings style with a sidebar and two tabs (General, Display).
- General tab: default duration slider (5 s – 10 min, two-zone snapping) + trackpad lock toggle.
- Display tab: overlay mode selector (Black Screen / HUD Only) + HUD corner picker (TL / TR / BR / BL).
- Explicit **Save** button in Settings; changes take effect on the next lock.
- HUD overlay mode: compact non-interactive countdown window per display, positioned at the user-configured corner.
- Trackpad Free mode: all pointing events pass through (cursor, clicks, scrolls); only keyboard is suppressed.
- Persist all settings to `UserDefaults`.

**Out of scope:**
- In-progress lock reconfiguration (settings changes apply to the next lock only).
- Custom preset durations beyond the 4 fixed values (15 s, 30 s, 1 min, 2 min).
- Per-display overlay mode (same mode applies to all connected displays).

### Data Model

```swift
// Persisted in UserDefaults (extend LockSettings)
struct LockSettings {
    var lastDuration: TimeInterval     // seconds, range 5–600, default 120
    var overlayMode: OverlayMode       // .blackScreen | .hud, default .blackScreen
    var trackpadMode: TrackpadMode     // .locked | .free, default .locked
    var hudCorner: HUDCorner           // .topLeft | .topRight | .bottomRight | .bottomLeft, default .bottomRight
}

enum OverlayMode: String { case blackScreen, hud }
enum TrackpadMode: String { case locked, free }
enum HUDCorner: String { case topLeft, topRight, bottomRight, bottomLeft }
```

### Duration Slider — Two-Zone Snapping

| Zone | Range | Step |
|---|---|---|
| Short | 5 s – 60 s | 5 s |
| Long | 1 min – 10 min | 1 min |

Total discrete values: 12 (short) + 9 (long) = 21 steps. The slider maps linearly to these 21 steps; the label updates live ("45 s", "3 min").

### Quick-Pick Menu (left-click on icon)

Fixed presets always shown: **15 s**, **30 s**, **1 min**, **2 min**.  
A fifth item (user's default, e.g. **"3 min (default)"**) appears only when the default value differs from all four fixed presets.  
Tapping any item calls `LockManager.startLock(duration:)` immediately; no further confirmation.

### UI Flows

#### Accessing Settings
1. User right-clicks the menu bar icon.
2. Contextual NSMenu shows: **Settings…** / separator / **Quit**.
3. Clicking **Settings…** opens (or focuses) the Settings window.

#### Settings Window
- Style: `NSWindow` with SwiftUI content; not `LSUIElement`-hidden (must be key-capable).
- Sidebar with two items: **General** and **Display**.
- **General tab:**
  - Lock Duration: two-zone slider with live value label (e.g. "2 min").
  - Trackpad: segmented control or toggle — **Locked** / **Free**.
- **Display tab:**
  - Overlay Mode: segmented control — **Black Screen** / **HUD Only**.
  - HUD Corner (enabled only when Overlay Mode = HUD Only): 2×2 corner picker or segmented control — TL / TR / BR / BL.
- Footer: **Save** button (primary) / **Cancel** button.
- Pressing **Save** writes to `UserDefaults` and closes the window.
- Pressing **Cancel** discards unsaved changes and closes.

#### Lock with HUD overlay
1. User picks a duration from the quick-pick menu.
2. `LockSettings.overlayMode == .hud`: `LockOverlayController` creates one compact `NSPanel` per `NSScreen`, sized ~200 × 80 pt, positioned at the configured corner (inset 20 pt from screen edge).
3. Panel content: countdown in large text, dim hint "Hold Esc × 3 to unlock".
4. Panel is non-interactive (`ignoresMouseEvents = true`); the CGEventTap layer still handles input blocking.
5. On unlock: all HUD panels are closed in the same teardown sequence as the full overlay.

#### Lock with Free Trackpad
1. `LockSettings.trackpadMode == .free`: CGEventTap callback passes through all `NSEventType.mouseMoved`, `.leftMouseDown`, `.leftMouseUp`, `.rightMouseDown`, `.rightMouseUp`, `.scrollWheel`, `.otherMouseDown`, `.otherMouseUp` events.
2. The callback drops only keyboard event types.
3. Cursor remains visible (CGDisplayShowCursor / NSCursor.unhide not called at lock start for this mode — or the app explicitly shows the cursor).
4. Emergency unlock (triple-Escape) still functional.

### Edge Cases

| Scenario | Handling |
|---|---|
| Default duration equals a fixed preset | Fifth item not shown in quick-pick menu (no duplicate) |
| Settings window open while lock starts | Lock starts normally; Settings window is dismissed or remains open (no modal block) |
| Display added/removed while locked with HUD | Rebuild HUD windows on `NSApplicationDidChangeScreenParametersNotification` (same as full overlay) |
| User saves Settings during an active lock | New settings apply to the next lock; in-progress lock is unaffected |
| HUD corner picker shown when Overlay = Black Screen | Corner picker control is disabled/greyed out in the UI (no effect on state) |
| Trackpad Free + emergency unlock | Triple-Escape still detected (keyboard events still blocked and monitored in tap callback) |
| Duration 5 s — very short lock | Valid; countdown starts, emergency combo still available |
| Duration default (120 s) equals no fixed preset | "2 min (default)" shown as 5th item since 120 s = 2 min matches the "2 min" fixed preset → NOT shown (duplicate suppressed) |

### Success Criteria

1. Left-clicking the menu bar icon shows the quick-pick NSMenu in ≤ 100 ms with correct preset labels.
2. Selecting a preset starts the lock within 200 ms.
3. The custom default appears as a 5th menu item if and only if it does not match 15 s, 30 s, 1 min, or 2 min.
4. Settings panel opens on right-click → Settings… and reflects current persisted values.
5. Save button persists all four settings to UserDefaults; Cancel discards changes.
6. In HUD mode, a compact countdown window appears on every connected display, positioned at the configured corner.
7. In Trackpad Free mode, cursor movement, clicks, and scrolls are not suppressed; keyboard events are.
8. All existing success criteria from v1 (triple-Escape, overlay accuracy, memory limits) continue to pass.
