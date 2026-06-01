import Foundation

// MARK: - SleepAssertionControlling

/// Wraps the two IOPMAssertion calls behind a testable seam.
///
/// Modelled on `EventTapControlling` — the real implementation calls
/// IOKit directly; tests inject a `FakeSleepAssertionController`.
@MainActor
public protocol SleepAssertionControlling: AnyObject {
  /// Creates sleep assertions according to `mode`.
  /// `.full` creates both display-sleep and idle-system-sleep assertions.
  /// `.systemOnly` creates only the idle-system-sleep assertion.
  /// Returns `false` on failure; on partial failure any succeeded assertion
  /// is released before returning so no half-created pair is left dangling.
  func createAssertions(reason: String, mode: KeepAwakeMode) -> Bool
  /// Releases both assertions if held. Idempotent.
  func releaseAssertions()
  /// `true` when both assertions are held.
  var isHeld: Bool { get }
}

// MARK: - PowerSourceObserving

/// Observes AC/battery transitions on the main run loop.
///
/// `start(onChange:)` fires once per power-source change with `isOnBattery`.
/// `stop()` removes the run-loop source and releases it.
/// The real conformer is `RealPowerSourceObserver`; tests inject `FakePowerSourceObserver`.
@MainActor
public protocol PowerSourceObserving: AnyObject {
  func start(onChange: @escaping (_ isOnBattery: Bool) -> Void)
  func stop()
}

// MARK: - BatteryWarningNotifying

/// Posts a user-visible battery-warning banner when keep-awake is active on battery.
///
/// Authorization is requested lazily on first `enable()`.
/// If permission is denied, `postBatteryWarning()` is a silent no-op (SPEC §7).
@MainActor
public protocol BatteryWarningNotifying: AnyObject {
  func requestAuthorizationIfNeeded()
  func postBatteryWarning()
  func clearBatteryWarning()
}
