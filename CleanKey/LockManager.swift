import CoreGraphics
import Foundation

/// The core lock/unlock state machine.
///
/// All side effects — overlay presentation, event-tap install/remove, and
/// user notifications — are injected via protocols so the logic is
/// unit-testable without CGEventTap or AppKit.
///
/// - Important: Must be used on the **main actor** (watchdog timer and state
///   mutations run on the main run loop).
@MainActor
public final class LockManager {

  // MARK: - Injected seams

  private let clock: @Sendable () -> Date
  private let tapController: EventTapControlling
  var presenter: any LockPresenting
  private let notifier: Notifying
  private let trustChecker: TrustChecking
  private let trackpadMode: @Sendable () -> TrackpadMode

  // MARK: - State

  public private(set) var state: LockState = .idle

  /// Wall-clock seconds remaining in the current lock, or 0 when idle.
  public var remainingTime: TimeInterval {
    guard case .locked(let endsAt, _) = state else { return 0 }
    return max(0, endsAt.timeIntervalSince(clock()))
  }

  // MARK: - Timer

  private var watchdogTimer: Timer?
  private var watchdogTickCount: Int = 0

  // MARK: - Constants

  /// Maximum inter-press interval for the triple-Escape combo (seconds).
  private static let escapeIntervalLimit: TimeInterval = 1.5

  // MARK: - Init

  public init(
    clock: @escaping @Sendable () -> Date = { Date() },
    tapController: EventTapControlling,
    presenter: LockPresenting,
    notifier: Notifying,
    trustChecker: TrustChecking? = nil,
    trackpadMode: @escaping @Sendable () -> TrackpadMode = { .locked }
  ) {
    self.clock = clock
    self.tapController = tapController
    self.presenter = presenter
    self.notifier = notifier
    self.trustChecker = trustChecker ?? AlwaysTrusted()
    self.trackpadMode = trackpadMode
  }

  // MARK: - Public API

  /// Starts a lock of `duration` seconds. No-op if already locked.
  public func startLock(duration: TimeInterval) {
    guard case .idle = state else { return }

    let endsAt = clock().addingTimeInterval(duration)
    state = .locked(endsAt: endsAt, escapeCombo: EscapeComboState())

    tapController.install(trackpadFree: trackpadMode() == .free)
    presenter.present()
    startWatchdogTimer()
  }

  /// Unlocks immediately, tearing down in the required order. Idempotent.
  public func unlock() {
    guard case .locked = state else { return }

    // Fixed teardown order: presenter → tap → timer → state.
    presenter.dismiss()
    tapController.remove()
    stopWatchdogTimer()
    state = .idle
  }

  // MARK: - Escape combo evaluator
  //
  // Called by the real CGEventTap callback (Task 6) or directly in tests.
  // Returns `true` if the combo completed and `unlock()` was called.

  @discardableResult
  public func evaluateEscapeCombo(keyCode: CGKeyCode, timestamp: TimeInterval) -> Bool {
    guard case .locked(let endsAt, var combo) = state else { return false }

    guard keyCode == 53 else {
      // Non-Escape key — reset the combo counter.
      combo.count = 0
      combo.lastTimestamp = nil
      state = .locked(endsAt: endsAt, escapeCombo: combo)
      return false
    }

    // Check inter-press interval.
    if let last = combo.lastTimestamp,
      (timestamp - last) > Self.escapeIntervalLimit
    {
      // Too slow — restart the count from 1 (this press is the new first).
      combo.count = 1
      combo.lastTimestamp = timestamp
      state = .locked(endsAt: endsAt, escapeCombo: combo)
      return false
    }

    combo.count += 1
    combo.lastTimestamp = timestamp
    state = .locked(endsAt: endsAt, escapeCombo: combo)

    if combo.count >= 3 {
      unlock()
      return true
    }

    return false
  }

  // MARK: - Watchdog

  /// Called by the real 1 s repeating timer or directly in tests.
  ///
  /// `count` is the 1-based tick number. Every 5th tick also checks
  /// `AXIsProcessTrusted` via the injected `trustChecker`.
  public func watchdogTick(count: Int) {
    guard case .locked(let endsAt, _) = state else { return }

    // Wall-clock expiry check.
    if clock() >= endsAt {
      unlock()
      return
    }

    // Tap-enabled check: if the OS has disabled the tap, fail safe immediately.
    if !tapController.isEnabled {
      notifier.post(
        message:
          "Lock ended early — Accessibility tap was disabled by macOS"
      )
      unlock()
      return
    }

    // Every 5th tick also verify Accessibility trust.
    if count % 5 == 0, !trustChecker.isTrusted {
      notifier.post(
        message:
          "Lock ended early — Accessibility permission was revoked"
      )
      unlock()
      return
    }

    // Drive overlay countdown — single source of truth for remaining time.
    presenter.tick(remainingTime: remainingTime)
  }

  // MARK: - Private helpers

  private func startWatchdogTimer() {
    stopWatchdogTimer()
    watchdogTickCount = 0
    // Timer fires on the main run loop, so the closure executes on the main
    // thread. MainActor-isolated state can be read/written safely here.
    watchdogTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
      [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated {
        self.watchdogTickCount += 1
        self.watchdogTick(count: self.watchdogTickCount)
      }
    }
  }

  private func stopWatchdogTimer() {
    watchdogTimer?.invalidate()
    watchdogTimer = nil
  }
}

private final class AlwaysTrusted: TrustChecking {
  var isTrusted: Bool { true }
}
