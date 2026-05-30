# CleanKey — Manual Integration Test Guide

Unit tests cover all pure logic. The scenarios below require a real Mac with
Accessibility permission granted, because CGEventTap cannot be exercised
in-process without the OS permission or a real event stream.

## Prerequisites

- macOS 14 Sonoma or later.
- Accessibility permission granted: System Settings > Privacy & Security > Accessibility > CleanKey (toggle ON).
- App built in Debug configuration and running (no Dock icon — check the menu bar).

---

## T1 — Keystroke suppression during lock

**Steps:**

1. Open TextEdit and place cursor in an empty document.
2. Click the CleanKey menu bar icon and start a 30-second lock.
3. Type on the keyboard.

**Expected:** no characters appear in TextEdit; the overlay covers the screen.

**Pass criteria:** zero characters typed during the lock window.

---

## T2 — Triple-Escape unlock within the 1.5 s window

**Steps:**

1. Start a 60-second lock.
2. Press Escape three times in rapid succession (each press within 1.5 s of the previous).

**Expected:** overlay dismisses within approximately 200 ms of the third press.

**Pass criteria:** unlock completes before any 4th key event is processed; no
characters appear in a text editor afterward.

---

## T3 — Triple-Escape with slow presses does NOT unlock

**Steps:**

1. Start a 60-second lock.
2. Press Escape, wait 2 seconds, press Escape again.
3. Wait 2 seconds. Press Escape.

**Expected:** lock remains active; the 2-second gap resets the combo counter
after the second press, so the third press is treated as count = 1.

**Pass criteria:** overlay stays visible; no unlock occurs.

---

## T4 — No event leak after unlock

**Steps:**

1. Start a 30-second lock.
2. Let the timer expire naturally.
3. Immediately type a sequence of keys and click the mouse.

**Expected:** all events are processed normally; no events are swallowed or
duplicated after unlock.

**Pass criteria:** characters appear in TextEdit as typed; mouse clicks register.

---

## T5 — Watchdog: Accessibility revocation mid-lock

**Steps:**

1. Start a 120-second lock.
2. Within 5 seconds of the lock starting, open System Settings > Privacy & Security > Accessibility and toggle CleanKey OFF.

**Expected:** within approximately 5 seconds (the watchdog's AXIsProcessTrusted
check fires every 5 ticks), the overlay dismisses and a notification appears:
"Lock ended early — Accessibility permission was revoked".

**Pass criteria:** input is restored; notification message matches exactly.

---

## T6 — Watchdog: OS tap disablement

This scenario requires a second tool that disables the tap (e.g., a CGEventTap
debugger or forcing the process trust check to fail). As a proxy:

**Steps:**

1. Start a lock.
2. Use Activity Monitor to send SIGSTOP to CleanKey, wait 3 seconds, then SIGCONT.

**Expected:** the watchdog fires within 1 s of SIGCONT and calls unlock.

**Pass criteria:** overlay is gone; input restored.

---

## T7 — Stage Manager coexistence (release blocker — ADR Decision 2)

**Steps:**

1. Enable Stage Manager (Control Center > Stage Manager ON).
2. Open two or more apps so Stage Manager is actively grouping windows.
3. Start a 15-second CleanKey lock.

**Expected:** the overlay covers all displays without being repositioned or
grouped by Stage Manager. On unlock, all Stage Manager windows return to their
previous positions.

**Pass criteria:** overlay is not visible in Stage Manager's window strip;
dismiss is clean. Record the macOS version and hardware in the test log.

**This test is a named release blocker for v1. Do not tag v1 without a
passing result on macOS 14 hardware.**

---

## T8 — Multi-display lock

**Steps:**

1. Connect an external display.
2. Start a lock.

**Expected:** one overlay window appears on each connected display.

**Pass criteria:** both displays are covered; unlock removes all overlays.

---

## T9 — Display hotplug while locked

**Steps:**

1. Start a lock.
2. Connect an external display mid-lock.

**Expected:** overlay rebuilds to include the new display within a short time.

**Pass criteria:** external display is covered without requiring a new lock cycle.

---

## T10 — Sleep/wake during lock

**Steps:**

1. Start a 120-second lock.
2. Immediately close the laptop lid (or trigger sleep via Apple menu).
3. Wait 5 seconds, then wake the machine.

**Expected:** the overlay reappears immediately on wake; the countdown reflects
elapsed wall-clock time (not the time while asleep); the lock expires correctly
when `Date()` reaches `endsAt`.

**Pass criteria:** overlay is present after wake; remaining time matches the
wall-clock elapsed interval; no duplicate overlays; unlock occurs at the
originally computed `endsAt`.

---

## T11 — Idle RAM usage (≤ 5 MB)

**Steps:**

1. Launch CleanKey (no lock started).
2. Wait 10 seconds for startup allocations to settle.
3. Open Activity Monitor, find CleanKey, read the Memory column.

**Pass criteria:** Real Mem ≤ 5 MB.

---

## T12 — Locked RAM usage (≤ 10 MB)

**Steps:**

1. Start a 60-second lock.
2. After the overlay is visible, read Real Mem in Activity Monitor.

**Pass criteria:** Real Mem ≤ 10 MB while locked.

---

## Pre-release checklist (run before tagging v1)

Record the macOS version, hardware, and result for each item.

| ID  | Scenario                                   | Result | macOS | Hardware | Date |
|-----|--------------------------------------------|--------|-------|----------|------|
| T1  | Keystroke suppression during lock          |        |       |          |      |
| T2  | Triple-Escape unlock within 1.5 s          |        |       |          |      |
| T3  | Slow Escape presses do NOT unlock          |        |       |          |      |
| T4  | No event leak after unlock                 |        |       |          |      |
| T5  | Accessibility revocation mid-lock          |        |       |          |      |
| T6  | OS tap disablement watchdog                |        |       |          |      |
| T7  | Stage Manager coexistence (release blocker)|        |       |          |      |
| T8  | Multi-display lock                         |        |       |          |      |
| T9  | Display hotplug while locked               |        |       |          |      |
| T10 | Sleep/wake during lock                     |        |       |          |      |
| T11 | Idle RAM ≤ 5 MB                            |        |       |          |      |
| T12 | Locked RAM ≤ 10 MB                         |        |       |          |      |

**T7 (Stage Manager) is a named release blocker.** Do not tag v1 without a
passing result recorded in the table above.

---

## Logging notes

When running any of these tests, attach Console.app and filter by `CleanKey`
to capture any unexpected errors from the CGEventTap or CoreGraphics stack.
