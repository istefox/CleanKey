# BRAINSTORM — CleanKey features before Gumroad release

**Date:** 2026-05-30
**Requirements source:** session dialogue + current codebase state (main branch)
**Techniques applied:** first-principles, prior-art, assumption-busting, inversion (pre-mortem), adjacent ideas

---

## Reframed problem (first-principles)

A user paying for CleanKey needs three things simultaneously: trigger the lock in zero steps, trust that nothing will go wrong during the clean, and feel that the app is worth money compared to what is already free. Any feature that scores on all three axes is a strong candidate. Features that score on only one are lower priority.

---

## Competitive landscape (prior-art)

| App | Price | Keyboard | Trackpad | Timer | Settings | Notable gap |
|---|---|---|---|---|---|---|
| KeyboardCleanTool | Free | lock | free only | none | none | No timer, no trackpad, no settings |
| KeyboardLocker | Free | lock | lock | none | none | Cmd+Q to unlock only, no timer |
| CleanupBuddy | Paid | lock | lock | ? | ? | Animated character angle |
| Mac Pause | Paid | lock | lock | ? | partial | Keyboard-only or pointer-only modes, launch-at-login |
| **CleanKey (current)** | — | lock | configurable | full | full | No launch-at-login, no keyboard-only mode |

**Differentiation spaces nobody fills well:**
1. Partial lock modes with a full settings panel (Mac Pause has modes but less settings depth)
2. Launch-at-login for a menu-bar cleaner (basic paid-app expectation, missing everywhere)
3. Proactive cleaning workflow (reminders, history)
4. Shortcuts/automation integration

---

## Challenged assumptions

- **One lock mode fits all hardware** — challenged. Some users only want keyboard-only (external keyboards, cleaning keys without touching the trackpad). Mac Pause already sells this. **Verdict: drop — add a keyboard-only mode.**
- **The app starts on demand** — challenged. A paid menu-bar app that disappears after a reboot loses the user. **Verdict: drop — launch-at-login is a baseline expectation for paid tools.**
- **Duration is the only parameter** — partially challenged. A physical-trigger unlock (plug in a cable) is novel and solves the "forgot the Escape combo" problem. **Verdict: interesting for v2, not a launch blocker.**

---

## Approach alternatives

### Alternative A — "Minimum paid baseline"

**Idea:** Add only the features that directly answer "why pay vs KeyboardCleanTool." Three additions: launch-at-login, sound feedback (lock/unlock), global hotkey.

**Axis of difference:** minimal scope, highest ROI per implementation day.

**Pros:**
- Launch-at-login alone makes the app feel real and paid-worthy.
- Sound feedback is visible/audible and absent from all free tools.
- Global hotkey (e.g., Option+Command+L) is a power-user hook with zero ongoing complexity.
- All three are already identified as ready seams in CLAUDE.md — very low implementation risk.

**Cons:**
- Does not address the keyboard-only mode gap vs Mac Pause.
- A determined reviewer can still argue "KeyboardCleanTool does the same core thing."

**Indicative cost/time:** low (1–2 days)

---

### Alternative B — "Clear differentiator set"

**Idea:** Alternative A plus a partial lock mode — keyboard-only (trackpad stays free) and trackpad-only (keyboard stays free). Directly fills the Mac Pause gap.

**Axis of difference:** new lock scope enum with 3 values (all, keyboardOnly, trackpadOnly) — event tap mask selection changes at install time.

**Pros:**
- Directly differentiates from KeyboardCleanTool (which only ever keeps trackpad free — CleanKey becomes MORE flexible).
- Answers "I just want to clean the keyboard, why does it block my mouse?" before users ask.
- Mac Pause charges for this; it belongs in a paid CleanKey.

**Cons:**
- New LockManager code path (changes event tap mask selection at install time).
- More settings surface to explain in onboarding.

**Indicative cost/time:** medium (2–3 days including tests)

---

### Alternative C — "Engagement and retention set"

**Idea:** Alternative A plus cleaning reminders (weekly/biweekly push notification) and a session counter (how many cleans this month, visible in menu or a stats popover).

**Axis of difference:** persistence model — needs UserDefaults for history; background scheduling with UserNotifications framework.

**Pros:**
- Cleaning reminders are a genuine differentiator — no competing app does this.
- Session stats make the app feel active and premium.
- Reminders drive re-engagement and reduce churn (user forgets the app without it).

**Cons:**
- Requires UserNotifications permission prompt on first run.
- Stats storage adds a lightweight data layer.

**Indicative cost/time:** medium (2–3 days)

---

### Alternative D — "Full pre-launch polish"

**Idea:** Alternatives B + C together, plus a proper first-launch onboarding flow for the Accessibility permission grant.

**Axis of difference:** scope and timeline — most complete pre-launch state.

**Pros:**
- Covers every identified gap in one release.
- Onboarding reduces "the app doesn't work" support emails (missing Accessibility permission).
- Positions CleanKey above all free and paid competitors.

**Cons:**
- Longer timeline before shipping anything.
- Risk of waiting for "complete" and shipping nothing.

**Indicative cost/time:** high (5–7 days)

---

## Risks emerged (inversion / pre-mortem)

- **"Why pay for this? KeyboardCleanTool is free and does the same."** — Mitigation: launch-at-login + sound + global hotkey + partial lock modes make the comparison obviously unequal. The Gumroad listing must surface these differences explicitly.
- **No launch-at-login means users forget the app exists** — Mitigation: P0 for any paid release. Without persistent presence, the app has no retention.
- **macOS update breaks the CGEventTap** — Mitigation: the app already has a watchdog that detects tap failure. Maintain a clear update policy (free updates within a major macOS version).
- **Partial lock mode adds event tap complexity** — Mitigation: the existing `trackpadMode` injection seam in LockManager absorbs much of this; the new scope parameter follows the same pattern.

---

## Adjacent ideas emerged

- **Cleaning reminders / schedule** — future v1.1 (strong differentiator, no competitor has it)
- **Session history / stats** — future v1.1 (engagement, premium feel)
- **Shortcuts / Siri Shortcuts integration** — future v1.1 (automation users, press coverage)
- **Physical-trigger unlock (USB plug/unplug via IOKit)** — future v2 (novel, solves "forgot Escape combo", non-trivial)
- **Menu bar countdown text** — low effort, worth v1.0 (makes countdown visible without opening the overlay)

---

## Preliminary recommendation

**Alternative B is the recommended pre-launch set**, with the three additions from A as prerequisites.

Priority order:
1. **Launch-at-login** (P0 — without it, a paid menu-bar app feels unfinished)
2. **Sound feedback** (P1 — audible and visible on the Gumroad listing, no free app has it)
3. **Global hotkey** (P1 — power-user hook, already a ready seam in CLAUDE.md)
4. **Keyboard-only lock mode** (P1 — fills the Mac Pause gap, directly answers the "why pay" objection)
5. **Menu bar countdown text** (P2 — small addition, makes the lock visible at a glance)

This is preliminary and should be validated before committing to scope.

---

## Notes for the architect

- **Launch-at-login:** use `SMAppService.mainApp.register()` (macOS 13+ API, no legacy helper target needed for macOS 14+ target).
- **Sound feedback:** `NSSound(named:)` or a bundled `.aiff` at lock start and unlock. Already flagged in CLAUDE.md v1.1 hooks as "no architectural change needed."
- **Global hotkey:** `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` with a configurable key combo stored in `LockSettings`. Already flagged in CLAUDE.md as a ready seam.
- **Keyboard-only mode:** extend the current `TrackpadMode` concept into a `LockScope` setting (all, keyboardOnly, trackpadOnly). The event tap mask in `RealEventTapController.install(trackpadFree:)` already accepts a parameter — extend it to accept a full scope enum. Tests exist for the current two-mode path; new scope values need new test coverage.
- **Menu bar countdown text:** set `statusItem.button?.title` to the remaining seconds on each watchdog tick. Low-risk addition.
