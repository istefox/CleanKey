# BRAINSTORM — CleanKey: Keyboard and Touchpad Lock for Cleaning

**Date:** 2026-05-29
**Requirements source:** /Users/stefanoferri/Developer/Apple/CleanKey/SPEC.md
**Techniques applied:** first-principles decomposition, assumption-busting, prior-art analysis, alternatives synthesis, inversion (pre-mortem), adjacent ideas

---

## Reframed problem (first-principles)

The irreducible need is: **complete isolation of the macOS session from all hardware input for a precisely known duration, without requiring re-authentication on resume.**

The screen blackout is a signal ("this is locked"), not a requirement in itself. The real requirement is that no keystroke or pointer event reaches the OS session while the hardware surface is being cleaned. Two physical facts constrain the solution: (1) macOS routes all HID events through the kernel and session event stream — suppression must happen at the session tap level or below; (2) the user must regain full control in finite time without a password.

---

## Challenged assumptions

- **Triple-Escape is safe from accidental firing during cleaning** — outcome: **retained**. Cleaning motions are random and variable; pressing the same key three times in 1.5 s is a deliberate rhythmic gesture that does not naturally emerge from wiping with a cloth. Real hardware testing is recommended in acceptance criteria.
- **Pre-set duration is the right lock model** — outcome: **retained**. Predictability ("know exactly when the Mac is usable again") is the stated preference. A manual-stop mode is technically possible but not desired for v1.
- **CGEventTap is the correct blocking mechanism** — outcome: **retained** (with caveats). The System Lock Bridge alternative (delegating to macOS screen lock) was evaluated and rejected: the system lock screen requires password re-authentication, which defeats the purpose of a 2-minute cleaning session.
- **Fullscreen overlay is necessary** — outcome: **retained as primary, with silent variant noted as future**. The overlay's main value is unambiguous "locked" signalling. A no-overlay (silent) mode is interesting for "lock while watching video" use cases but is deferred.

---

## Approach alternatives

### Alternative A — Full Lock (current SPEC)

- **Idea:** CGEventTap at `cgSessionEventTap` suppresses all keyboard and pointer events. A fullscreen dark `NSWindow` at `Level.screenSaver` covers every display. Live countdown displayed. Triple-Escape unlocks.
- **Axis of difference:** complete visual + input isolation (overlay + tap)
- **Pros:** no ambiguity about lock state; strongest "do not touch" signal; works regardless of what app is in foreground
- **Cons:** two subsystems to coordinate (tap + overlay windows); display hotplug complexity; window level may conflict with Stage Manager (see risks)
- **Indicative cost/time:** medium

### Alternative B — Silent Lock

- **Idea:** same CGEventTap input suppression, but NO fullscreen overlay. The menu bar icon displays a live countdown (text badge: "1:45"). The desktop remains fully visible. Unlock via triple-Escape or timer expiry.
- **Axis of difference:** responsibility boundary — window management eliminated; lock state expressed only via menu bar icon
- **Pros:** no window level conflicts; no display hotplug logic; useful for "clean while watching a video"; simpler codebase
- **Cons:** weak "locked" signal — returning users may not notice the Mac is still locked; no visual deterrent for bystanders
- **Indicative cost/time:** low
- **Status:** deferred to v1.1; worth a feature flag in the architecture so it can be added without a rewrite

### Alternative C — System Lock Bridge *(rejected)*

- **Idea:** delegate blocking to macOS's own screen lock (`CGSession` lock). A timer triggers lock; on expiry, auto-unlock via scripting bridge. No Accessibility permission required.
- **Axis of difference:** responsibility boundary — blocking fully delegated to OS; no custom event tap
- **Pros:** zero permission friction; guaranteed OS-level reliability
- **Cons:** **deal-breaker** — the system lock screen requires password re-authentication. A 2-minute cleaning session must not force a password entry on return. Rejected.
- **Indicative cost/time:** n/a (rejected)

---

## Risks emerged (inversion / pre-mortem)

- **CGEventTap watchdog invalidation while overlay is still showing** → the OS silently kills misbehaving event taps; the overlay remains on screen but input flows through uninhibited; the user types a password or sends a message while thinking the Mac is locked.
  Mitigation: 1-second `CGEventTapIsEnabled` poll inside `LockManager`; on false result, immediately destroy overlay windows, remove tap reference, surface a user notification: "Lock ended early — Accessibility tap was disabled by macOS."

- **Fullscreen overlay window level conflicts with Stage Manager / full-screen apps** → on macOS 14+ with Stage Manager enabled, `NSWindow.Level.screenSaver` may compete with system-managed window groups, causing display glitches, forced app exits, or windows that cannot be dismissed.
  Mitigation: acceptance test on macOS 14 Sonoma with Stage Manager on; validate that `collectionBehavior: .canJoinAllSpaces + .fullScreenAuxiliary` prevents Stage Manager from repositioning the overlay; add a regression note in the ADR.

---

## Adjacent ideas emerged

- **Global hotkey to trigger lock** — [future v1.1] A configurable `NSEvent.addGlobalMonitorForEvents`-based shortcut to start the last-used lock from any app, without touching the menu bar. The architecture should plan for this: `LockManager.startLock()` is already decoupled from the UI; adding a hotkey is a registration call.
- **Sound feedback on lock start / unlock** — [future v1.1] A soft system sound (`NSSound`) on lock start and a distinct tone on unlock/expiry. Useful when the user's eyes are on the keyboard, not the screen. Zero architectural impact; trivial to add.
- **Silent Lock mode (no overlay)** — [future v1.1] Alternative B above. Could be a toggle ("Full / Silent") in the popover. Requires no architectural changes to LockManager; only the overlay creation step is conditional.

---

## Preliminary recommendation

**Alternative A (Full Lock) is the correct choice for v1.** It is the only approach that completely matches the stated differentiation goals: timer countdown, full input block (keyboard + trackpad), multi-display overlay, modern notarized distribution. No competing alternative is both architecturally sound and user-experience-complete for the cleaning use case.

The two risks identified in the pre-mortem are **architecturally significant and must be addressed in the ADR**, not deferred:
1. The watchdog poll (`CGEventTapIsEnabled` on a 1-second `Timer`) must be part of the design, not an afterthought.
2. Stage Manager window level compatibility must be an explicit acceptance criterion with a named test case.

---

## Notes for the architect

1. **Watchdog poll is load-bearing**: design `LockManager` with a `Timer`-based health check that calls `CGEventTapIsEnabled`; on false, call `unlock()` and post a notification before the user discovers the failure themselves.
2. **Stage Manager test case**: document in the ADR that `NSWindow.Level.screenSaver` + `collectionBehavior` must be validated on macOS 14 with Stage Manager enabled before v1 ships.
3. **Silent Lock hook**: plan `LockOverlayController` as an optional component (not hard-wired); this makes the Alternative B future feature a 1-line conditional, not a refactor.
4. **Global hotkey future path**: `LockManager.startLock(duration:)` should be a clean entry point with no UI dependency, so a future hotkey registration can call it directly.
5. **MAS entitlements**: `com.apple.security.device.input-monitoring` must appear in the `.entitlements` file from day one; missing it blocks the MAS path without a signing rebuild.
6. **AXIsProcessTrusted() revocation**: the watchdog should also check `AXIsProcessTrusted()` every 5 s while locked; if it returns false, treat it the same as watchdog invalidation.
