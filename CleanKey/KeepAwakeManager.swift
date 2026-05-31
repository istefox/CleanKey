import Foundation

/// The keep-awake enable/disable state machine.
///
/// Mirrors `LockManager`'s shape: all side effects (IOPMAssertion, power
/// observer, user notifications) are injected behind protocols so the core
/// is unit-testable with fakes and no real IOKit or UserNotifications calls.
///
/// - Important: Must be used on the **main actor** (timer and state mutations
///   run on the main run loop, mirroring the LockManager convention).
@MainActor
public final class KeepAwakeManager {

  // MARK: - Injected seams

  private let assertions: any SleepAssertionControlling
  private let powerObserver: any PowerSourceObserving
  private let notifier: any BatteryWarningNotifying
  private let capProvider: @Sendable () -> TimeInterval
  /// Called after every `enable()` and `disable()`. `MenuBarController` overwrites
  /// this after construction to wire the icon update (ADR-003 D3).
  public var onChange: () -> Void
  private let persist: (Bool) -> Void

  // MARK: - State

  /// `true` when both IOPMAssertions are held (derived from the assertion controller).
  public var isActive: Bool { assertions.isHeld }

  // MARK: - Cap timer

  private var capTimer: Timer?

  // MARK: - Init

  public init(
    assertions: any SleepAssertionControlling,
    powerObserver: any PowerSourceObserving,
    notifier: any BatteryWarningNotifying,
    capProvider: @escaping @Sendable () -> TimeInterval = { 0 },
    onChange: @escaping () -> Void = {},
    persist: @escaping (Bool) -> Void = { _ in }
  ) {
    self.assertions = assertions
    self.powerObserver = powerObserver
    self.notifier = notifier
    self.capProvider = capProvider
    self.onChange = onChange
    self.persist = persist
  }

  // MARK: - Public API

  /// Enables keep-awake. Idempotent — no-op if already active.
  public func enable() {
    guard !assertions.isHeld else { return }

    notifier.requestAuthorizationIfNeeded()

    guard assertions.createAssertions(reason: "CleanKey Keep Awake") else {
      // Failed to acquire assertions — stay inactive, no observer, no callback.
      return
    }

    powerObserver.start { [weak self] isOnBattery in
      guard let self, self.isActive else { return }
      if isOnBattery {
        self.notifier.postBatteryWarning()
      }
    }

    let cap = capProvider()
    if cap > 0 {
      startCapTimer(duration: cap)
    }

    persist(true)
    onChange()
  }

  /// Disables keep-awake. Idempotent — no-op if already inactive.
  ///
  /// Fixed teardown order (ADR-003 D2):
  ///   stop cap timer → stop power observer → release assertions → clearBatteryWarning → persist → onChange
  public func disable() {
    guard assertions.isHeld else { return }

    stopCapTimer()
    powerObserver.stop()
    assertions.releaseAssertions()
    notifier.clearBatteryWarning()
    persist(false)
    onChange()
  }

  // MARK: - Cap timer

  /// Called by the real `Timer` closure and directly in unit tests.
  func capTimerFired() {
    disable()
  }

  // MARK: - Private helpers

  private func startCapTimer(duration: TimeInterval) {
    stopCapTimer()
    capTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
      [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.capTimerFired()
      }
    }
  }

  private func stopCapTimer() {
    capTimer?.invalidate()
    capTimer = nil
  }
}
