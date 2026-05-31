# BRAINSTORM — Keep-Awake Feature Addition to CleanKey

**Date:** 2026-05-31
**Requirements source:** SPEC-keep-awake.md
**Techniques applied:** first-principles, assumption-busting, prior-art, alternatives synthesis, inversion/pre-mortem, adjacent ideas

---

## Reframed problem (first-principles)

The irreducible need is not "prevent sleep" — it is **architectural parity with `LockManager`**.
Keep-awake must feel like a first-class peer of the lock feature, not a bolt-on module.
This means same protocol idioms, same settings integration pattern, same menu-bar state model.
The assertion lifecycle (enable/release) is the mechanism; parity is the design constraint.

---

## Challenged assumptions

- **`KeepAwakeManager` must be a separate type from `LockManager`** — *worth challenging*. A single `AppCoordinator` could own both as subsystems under a shared interface. Retained as separate managers (different lifecycles: timer+event-tap vs. toggle+IOPMAssertion) but coordinated via a mediator.
- **`AppDisplayState` enum is needed to bridge the two managers** — *habit, dropped*. `MenuBarController` can derive icon state inline from two `@Observable` boolean properties (`isLocked`, `isAwake`). No bridge type needed.
- **Power-source monitoring belongs inside `KeepAwakeManager`** — *real constraint, retained*. Only `KeepAwakeManager` reacts to battery events. A shared `PowerSourceMonitor` service would be YAGNI for a single consumer.
- **Caffeine's architecture is the reference** — *challenged*. Our differentiation is the bundle (lock + awake in one agent), not feature depth. Don't try to out-Caffeine Caffeine.

---

## Approach alternatives

### Alternative A — Parallel peers (SPEC's original direction)

- **Idea:** `KeepAwakeManager` is a standalone `@MainActor` class alongside `LockManager`. `AppDelegate` owns both. `MenuBarController` observes `isLocked` and `isAwake` directly and derives icon state inline.
- **Axis of difference:** responsibility boundary — no shared coordinator; each manager is fully self-contained.
- **Pros:** minimal new types; consistent with existing code structure; easy to test each manager in isolation.
- **Cons:** `MenuBarController` carries icon-derivation logic; cross-feature interactions (e.g. a future "both" preset) need to be added somewhere ad hoc.
- **Indicative cost/time:** low.

### Alternative B — AppCoordinator mediator (preliminary recommendation)

- **Idea:** new `AppCoordinator` type (owned by `AppDelegate`) holds both `LockManager` and `KeepAwakeManager`. It is the single `@Observable` source of truth for the menu bar. `MenuBarController` observes only the coordinator. Coordinator derives display state from `isLocked ⊕ isAwake`.
- **Axis of difference:** data model — single derived-state owner; managers remain pure (logic-only, no UI awareness).
- **Pros:** single observation point in `MenuBarController`; cross-feature interactions live in one place; coordinator can debounce re-render bursts; clean seam for future preset/scheduling logic.
- **Cons:** one additional type; risk of coordinator becoming a god object if boundaries are not enforced.
- **Mitigation (pre-mortem):** coordinator derives state only — zero logic, zero side effects. All capability logic stays inside the individual managers. Enforced by contract: coordinator accepts two read-only `isActive` sources and emits `AppDisplayState`. Tests target managers directly; coordinator has a trivial unit test.
- **Indicative cost/time:** medium (one new type + wiring).

### Alternative C — Protocol-unified (`FeatureManaging`)

- **Idea:** extract `FeatureManaging` protocol (`enable()`, `disable()`, `isActive: Bool`). Both managers conform. `AppDelegate` holds `[any FeatureManaging]` and derives display state by iterating.
- **Axis of difference:** concurrency/boundary — uniform interface enables future features to plug in without coordinator changes.
- **Pros:** most extensible; `AppDelegate` stays the coordinator.
- **Cons:** premature abstraction with only two conformers; `[any FeatureManaging]` loses type safety for per-feature configuration; harder to derive a 4-state icon from a homogeneous array.
- **Indicative cost/time:** medium.

---

## Risks emerged (inversion / pre-mortem)

- **Coordinator boundary erosion** → `AppCoordinator` accumulates logic and becomes untestable. *Mitigation: strict contract — coordinator is read-only state derivation only; tested with stub managers.*
- **IOPMAssertion leak on crash/force-quit** → machine stays awake after abnormal exit. *Mitigation: `atexit` handler + `applicationWillTerminate` + optional watchdog.*
- **Re-render storms** → two `@Observable` managers changing simultaneously cause multiple SwiftUI update cycles. *Mitigation: coordinator coalesces both changes into one derived state update.*

---

## Adjacent ideas emerged

- **"Presentation mode" preset** — one tap activates both lock and keep-awake simultaneously. Named presets (future). *Status: future — note in ADR as extension hook.*
- **Scheduled keep-awake** — auto-enable between configurable hours. *Status: future — `AppCoordinator` is the natural insertion point.*
- **Cap countdown in status item title** — if a duration cap is set, show remaining time (e.g. "3h 22m") in title, mirroring the lock countdown. *Status: future — reuses `PresenterProxy.onTick` pattern cleanly.*

---

## Preliminary recommendation

**Alternative B (AppCoordinator mediator)** is preliminarily recommended. It is the only architecture that gives the bundle a single testable state source and a natural home for future cross-feature interactions, without coupling the two managers to each other. The god-object risk is real but fully mitigable by a strict "derive-only" contract. Alternative A is the safe fallback if the coordinator feels like over-engineering for v1.

*This recommendation is preliminary — the architect validates and decides in the ADR.*

---

## Notes for the architect

- Verify whether `IOPSNotificationCreateRunLoopSource` requires entitlements on macOS 14+ (sandbox is OFF for the DMG build, but worth confirming).
- Decide coordinator name: `AppCoordinator` vs. extending `AppDelegate` with a nested type.
- `AppDisplayState` enum from the SPEC is dropped in favour of inline derivation — confirm acceptable for 4-icon switching logic.
- All three adjacent ideas (preset, scheduled, cap countdown) should appear in ADR "Future extensions" as explicit hooks, not dead code.
- `UNUserNotificationCenter` requires a usage description in `Info.plist` — confirm it is absent today and add it.
