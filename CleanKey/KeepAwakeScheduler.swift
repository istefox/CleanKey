import Foundation

/// Watches wall-clock time and calls onStart/onEnd at the right moments.
///
/// Owns a 1 s repeating watchdog (same ADR-001 pattern as LockManager).
/// The clock, onStart, and onEnd are all injected so the class is unit-testable
/// without real timers or side effects.
@MainActor
public final class KeepAwakeScheduler {

  // MARK: - Injected seams

  private let clock: () -> Date
  private let onStart: () -> Void
  private let onEnd: () -> Void

  // MARK: - State

  private(set) public var armedSchedule: KeepAwakeSchedule?
  private var hasStarted = false
  private var watchdog: Timer?

  // MARK: - Init

  public init(
    clock: @escaping () -> Date = Date.init,
    onStart: @escaping () -> Void,
    onEnd: @escaping () -> Void
  ) {
    self.clock = clock
    self.onStart = onStart
    self.onEnd = onEnd
  }

  // MARK: - Public API

  /// Arms the scheduler. If startDate is nil, fires onStart immediately.
  public func arm(_ schedule: KeepAwakeSchedule) {
    clear()
    armedSchedule = schedule
    hasStarted = false

    if schedule.startDate == nil {
      onStart()
      hasStarted = true
    }

    startWatchdog()
  }

  /// Stops the watchdog and drops the schedule. Idempotent.
  /// Teardown order: stop timer → clear state.
  public func clear() {
    watchdog?.invalidate()
    watchdog = nil
    armedSchedule = nil
    hasStarted = false
  }

  // MARK: - Watchdog tick (test seam)

  func tick() {
    guard let schedule = armedSchedule else { return }
    let now = clock()

    if now >= schedule.endDate {
      onEnd()
      clear()
      return
    }

    if !hasStarted {
      if let start = schedule.startDate {
        if now >= start {
          onStart()
          hasStarted = true
        }
      } else {
        // startDate == nil means onStart was already fired in arm(); mark started.
        hasStarted = true
      }
    }
  }

  // MARK: - Private helpers

  private func startWatchdog() {
    watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated { self.tick() }
    }
  }
}
