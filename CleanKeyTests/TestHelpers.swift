import XCTest

@testable import CleanKey

// MARK: - Clock box

// @unchecked Sendable is safe: ClockBox is only ever mutated from @MainActor test methods.
final class ClockBox: @unchecked Sendable {
  var now: Date
  init(_ date: Date = Date(timeIntervalSince1970: 0)) { now = date }
}

// MARK: - Shared fakes

@MainActor
final class FakeLockPresenter: LockPresenting {
  var presentCallCount = 0
  var dismissCallCount = 0

  func present() { presentCallCount += 1 }
  func dismiss() { dismissCallCount += 1 }
}

@MainActor
final class FakeEventTapController: EventTapControlling {
  var installCallCount = 0
  var removeCallCount = 0
  var isEnabled: Bool = true
  var lastInstallScope: LockScope?

  func install(scope: LockScope) {
    installCallCount += 1
    lastInstallScope = scope
  }
  func remove() { removeCallCount += 1 }
}

// @unchecked Sendable is safe: only ever mutated from @MainActor contexts (LockManager is @MainActor).
final class FakeNotifier: Notifying, @unchecked Sendable {
  var messages: [String] = []
  func post(message: String) { messages.append(message) }
}

// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
final class FakeTrustChecker: TrustChecking, @unchecked Sendable {
  var trusted: Bool = true
  var isTrusted: Bool { trusted }
}

// MARK: - Sound fake

// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
final class FakeSoundPlayer: SoundPlaying, @unchecked Sendable {
  var played: [FeedbackSound] = []
  func play(_ sound: FeedbackSound) { played.append(sound) }
}

// MARK: - LaunchAtLogin fake

// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
final class FakeLaunchAtLogin: LaunchAtLoginControlling, @unchecked Sendable {
  var lastApplied: Bool?
  func apply(_ enabled: Bool) { lastApplied = enabled }
}

// MARK: - Keep-Awake fakes

/// Records create/release calls. `createShouldFail` makes `createAssertions` return `false`.
/// `isHeld` is derived from the net create/release balance and the fail flag.
// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
@MainActor
final class FakeSleepAssertionController: SleepAssertionControlling, @unchecked Sendable {
  var createCallCount = 0
  var releaseCallCount = 0
  var createShouldFail = false

  var isHeld: Bool {
    guard !createShouldFail else { return false }
    return createCallCount > releaseCallCount
  }

  func createAssertions(reason: String) -> Bool {
    createCallCount += 1
    return !createShouldFail
  }

  /// Called after incrementing `releaseCallCount`. Wire this in tests to record ordering.
  var onRelease: (() -> Void)?

  func releaseAssertions() {
    releaseCallCount += 1
    onRelease?()
  }
}

// MARK: - Keep-Awake fakes (power observer + battery notifier)

/// Records start/stop calls and lets tests trigger the onChange callback manually.
// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
@MainActor
final class FakePowerSourceObserver: PowerSourceObserving, @unchecked Sendable {
  var startCallCount = 0
  var stopCallCount = 0
  private(set) var onChange: ((_ isOnBattery: Bool) -> Void)?

  func start(onChange: @escaping (_ isOnBattery: Bool) -> Void) {
    startCallCount += 1
    self.onChange = onChange
  }

  /// Called after incrementing `stopCallCount`. Wire this in tests to record ordering.
  var onStop: (() -> Void)?

  func stop() {
    stopCallCount += 1
    onStop?()
    onChange = nil
  }

  /// Simulate a power-source change event in tests.
  func fireOnChange(isOnBattery: Bool) {
    onChange?(isOnBattery)
  }
}

/// Records authorization and warning calls; never touches UNUserNotificationCenter.
@MainActor
final class FakeBatteryWarningNotifier: BatteryWarningNotifying {
  var requestAuthorizationCallCount = 0
  var postBatteryWarningCallCount = 0
  var clearBatteryWarningCallCount = 0

  /// Called after incrementing `clearBatteryWarningCallCount`. Wire this in tests to record ordering.
  var onClear: (() -> Void)?

  func requestAuthorizationIfNeeded() { requestAuthorizationCallCount += 1 }
  func postBatteryWarning() { postBatteryWarningCallCount += 1 }
  func clearBatteryWarning() {
    clearBatteryWarningCallCount += 1
    onClear?()
  }
}

// MARK: - LockState test-only Equatable
// WARNING: ignores escapeCombo — .locked states with different combo progress compare equal.
// Use pattern matching (guard case .locked = state) when combo content matters.
extension LockState: Equatable {
  public static func == (lhs: LockState, rhs: LockState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle): return true
    case (.locked(let la, _), .locked(let ra, _)): return la == ra
    default: return false
    }
  }
}
