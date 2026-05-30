import XCTest

@testable import CleanKey

// MARK: - Fakes (watchdog-specific)

/// Fake tap controller that also exposes a mutable `isEnabled` flag.
// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
final class FakeEnabledTapController: EventTapControlling, @unchecked Sendable {
  var installCallCount = 0
  var removeCallCount = 0
  var enabled: Bool = true

  func install(trackpadFree: Bool) { installCallCount += 1 }
  func remove() { removeCallCount += 1 }
  var isEnabled: Bool { enabled }
}

// MARK: - WatchdogTests

@MainActor
final class WatchdogTests: XCTestCase {

  // MARK: - Helpers

  private func makeSUT(
    clockNow: Date = Date(timeIntervalSince1970: 1_000),
    tapEnabled: Bool = true,
    trusted: Bool = true
  ) -> (
    sut: LockManager,
    clock: ClockBox,
    tap: FakeEnabledTapController,
    presenter: FakeLockPresenter,
    notifier: FakeNotifier,
    trustChecker: FakeTrustChecker
  ) {
    let clock = ClockBox(clockNow)
    let tap = FakeEnabledTapController()
    tap.enabled = tapEnabled
    let presenter = FakeLockPresenter()
    let notifier = FakeNotifier()
    let trustChecker = FakeTrustChecker()
    trustChecker.trusted = trusted
    let sut = LockManager(
      clock: { clock.now },
      tapController: tap,
      presenter: presenter,
      notifier: notifier,
      trustChecker: trustChecker
    )
    return (sut, clock, tap, presenter, notifier, trustChecker)
  }

  // MARK: - Tap reports enabled → no action

  func testWatchdogTickWhenTapEnabledAndTrustedDoesNothing() {
    let (sut, _, tap, presenter, notifier, _) = makeSUT()
    sut.startLock(duration: 60)

    sut.watchdogTick(count: 1)

    XCTAssertNotEqual(sut.state, .idle, "Lock must remain active")
    XCTAssertEqual(tap.removeCallCount, 0, "Tap must not be removed")
    XCTAssertEqual(presenter.dismissCallCount, 0, "Overlay must not be dismissed")
    XCTAssertTrue(notifier.messages.isEmpty, "No notification must be posted")
  }

  // MARK: - Tap reports disabled → fail-safe unlock + notification

  func testWatchdogTickWhenTapDisabledUnlocksAndNotifies() {
    let (sut, _, tap, presenter, notifier, _) = makeSUT(tapEnabled: false)
    sut.startLock(duration: 60)

    sut.watchdogTick(count: 1)

    XCTAssertEqual(sut.state, .idle, "Must unlock when tap is disabled")
    XCTAssertEqual(presenter.dismissCallCount, 1, "Overlay must be dismissed")
    XCTAssertEqual(tap.removeCallCount, 1, "Tap must be removed")
    XCTAssertFalse(
      notifier.messages.isEmpty,
      "A notification must be posted when tap is disabled"
    )
  }

  func testWatchdogTickDisabledTapNotifiesOnlyOnce() {
    let (sut, _, _, _, notifier, _) = makeSUT(tapEnabled: false)
    sut.startLock(duration: 60)

    sut.watchdogTick(count: 1)
    // Second tick after unlock: state is idle, so tick is a no-op.
    sut.watchdogTick(count: 2)

    XCTAssertEqual(notifier.messages.count, 1, "Notification must be posted exactly once")
  }

  // MARK: - 5th tick checks AXIsProcessTrusted

  func testWatchdogFifthTickWhenNotTrustedUnlocksAndNotifies() {
    let (sut, _, tap, presenter, notifier, trustChecker) = makeSUT()
    trustChecker.trusted = false
    sut.startLock(duration: 60)

    // Ticks 1–4 must not trigger (tap is still enabled, trust not checked yet).
    sut.watchdogTick(count: 1)
    sut.watchdogTick(count: 2)
    sut.watchdogTick(count: 3)
    sut.watchdogTick(count: 4)
    XCTAssertNotEqual(sut.state, .idle, "Must still be locked before the 5th tick")

    sut.watchdogTick(count: 5)

    XCTAssertEqual(sut.state, .idle, "Must unlock on 5th tick when trust revoked")
    XCTAssertEqual(presenter.dismissCallCount, 1)
    XCTAssertEqual(tap.removeCallCount, 1)
    XCTAssertFalse(notifier.messages.isEmpty)
  }

  func testWatchdogNonFifthTicksDoNotCheckTrust() {
    // Trust is revoked but we never reach the 5th tick: must stay locked.
    let (sut, _, _, _, _, trustChecker) = makeSUT()
    trustChecker.trusted = false
    sut.startLock(duration: 60)

    sut.watchdogTick(count: 1)
    sut.watchdogTick(count: 2)
    sut.watchdogTick(count: 3)
    sut.watchdogTick(count: 4)

    XCTAssertNotEqual(sut.state, .idle, "Must not unlock before the 5th tick")
  }

  func testWatchdogTenthTickAlsoChecksTrust() {
    // count % 5 == 0 fires at tick 5, 10, 15 …
    // Revoke trust only after tick 5 has passed to verify tick 10 independently.
    let (sut, _, _, presenter, notifier, trustChecker) = makeSUT()
    sut.startLock(duration: 60)

    // Ticks 1–9: trust is still valid so no unlock.
    for count in 1...9 {
      sut.watchdogTick(count: count)
    }
    XCTAssertNotEqual(sut.state, .idle, "Must still be locked before the 10th tick")

    // Revoke trust just before tick 10.
    trustChecker.trusted = false
    sut.watchdogTick(count: 10)

    XCTAssertEqual(sut.state, .idle, "Must unlock on 10th tick when trust revoked")
    XCTAssertEqual(presenter.dismissCallCount, 1)
    XCTAssertFalse(notifier.messages.isEmpty)
  }

  // MARK: - Teardown order: presenter dismissed before tap removed

  func testWatchdogTeardownOrderPresenterBeforeTap() {
    var callOrder: [String] = []

    final class OrderedPresenter: LockPresenting {
      let log: (String) -> Void
      init(log: @escaping (String) -> Void) { self.log = log }
      func present() {}
      func dismiss() { log("presenter.dismiss") }
    }

    final class OrderedTap: EventTapControlling, @unchecked Sendable {
      let log: (String) -> Void
      var isEnabled: Bool = false  // disabled → triggers fail-safe
      init(log: @escaping (String) -> Void) { self.log = log }
      func install(trackpadFree: Bool) {}
      func remove() { log("tap.remove") }
    }

    let clock = ClockBox(Date(timeIntervalSince1970: 1_000))
    let trustChecker = FakeTrustChecker()
    let sut = LockManager(
      clock: { clock.now },
      tapController: OrderedTap { callOrder.append($0) },
      presenter: OrderedPresenter { callOrder.append($0) },
      notifier: FakeNotifier(),
      trustChecker: trustChecker
    )

    sut.startLock(duration: 60)
    sut.watchdogTick(count: 1)  // tap.isEnabled == false → fail-safe teardown

    XCTAssertEqual(
      callOrder, ["presenter.dismiss", "tap.remove"],
      "presenter.dismiss must precede tap.remove in watchdog teardown"
    )
  }
}
