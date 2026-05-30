import XCTest

@testable import CleanKey

// MARK: - State Machine Tests

@MainActor
final class LockManagerStateTests: XCTestCase {

  // MARK: - Helpers

  private func makeSUT(clock: ClockBox = ClockBox()) -> (
    LockManager, FakeLockPresenter, FakeEventTapController, FakeNotifier
  ) {
    let presenter = FakeLockPresenter()
    let tapController = FakeEventTapController()
    let notifier = FakeNotifier()
    let trustChecker = FakeTrustChecker()
    let sut = LockManager(
      clock: { clock.now },
      tapController: tapController,
      presenter: presenter,
      notifier: notifier,
      trustChecker: trustChecker
    )
    return (sut, presenter, tapController, notifier)
  }

  // MARK: - startLock: idle → locked

  func testStartLockFromIdleTransitionsToLocked() {
    let clock = ClockBox(Date(timeIntervalSince1970: 1_000))
    let (sut, _, _, _) = makeSUT(clock: clock)

    sut.startLock(duration: 60)

    guard case .locked(let endsAt, _) = sut.state else {
      XCTFail("Expected .locked, got \(sut.state)")
      return
    }
    let expected = clock.now.addingTimeInterval(60)
    XCTAssertEqual(
      endsAt.timeIntervalSince1970,
      expected.timeIntervalSince1970,
      accuracy: 0.001
    )
  }

  func testStartLockInstallsTapAndCallsPresenter() {
    let (sut, presenter, tapController, _) = makeSUT()

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.installCallCount, 1)
    XCTAssertEqual(presenter.presentCallCount, 1)
  }

  func testStartLockIsNotReentrant() {
    let (sut, _, tapController, _) = makeSUT()

    sut.startLock(duration: 60)
    sut.startLock(duration: 90)  // second call must be ignored

    XCTAssertEqual(tapController.installCallCount, 1, "Tap must only be installed once")
  }

  // MARK: - Wall-clock expiry

  func testTimerExpiryUnlocksWhenClockAdvancesPastEndsAt() {
    let clock = ClockBox(Date(timeIntervalSince1970: 1_000))
    let (sut, presenter, tapController, _) = makeSUT(clock: clock)

    sut.startLock(duration: 30)
    clock.now = clock.now.addingTimeInterval(31)
    sut.watchdogTick(count: 1)

    XCTAssertEqual(sut.state, .idle)
    XCTAssertEqual(presenter.dismissCallCount, 1)
    XCTAssertEqual(tapController.removeCallCount, 1)
  }

  func testRemainingTimeDecreasesWithAdvancingClock() {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let (sut, _, _, _) = makeSUT(clock: clock)

    sut.startLock(duration: 60)
    clock.now = clock.now.addingTimeInterval(20)

    XCTAssertEqual(sut.remainingTime, 40, accuracy: 0.01)
  }

  func testRemainingTimeIsZeroAtExactExpiry() {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let (sut, _, _, _) = makeSUT(clock: clock)

    sut.startLock(duration: 30)
    clock.now = clock.now.addingTimeInterval(30)  // exactly at endsAt

    XCTAssertEqual(sut.remainingTime, 0, accuracy: 0.001)
  }

  func testRemainingTimeDoesNotGoNegative() {
    let clock = ClockBox(Date(timeIntervalSince1970: 0))
    let (sut, _, _, _) = makeSUT(clock: clock)

    sut.startLock(duration: 30)
    clock.now = clock.now.addingTimeInterval(60)  // well past endsAt

    XCTAssertEqual(sut.remainingTime, 0, accuracy: 0.001)
  }

  // MARK: - unlock()

  func testUnlockFromLockedReturnsToIdle() {
    let (sut, _, _, _) = makeSUT()

    sut.startLock(duration: 60)
    sut.unlock()

    XCTAssertEqual(sut.state, .idle)
  }

  func testUnlockTeardownOrderPresenterBeforeTap() {
    // Record call order to assert presenter.dismiss() precedes tap.remove().
    var callOrder: [String] = []

    final class OrderedPresenter: LockPresenting {
      let log: (String) -> Void
      init(log: @escaping (String) -> Void) { self.log = log }
      func present() {}
      func dismiss() { log("presenter.dismiss") }
    }
    final class OrderedTap: EventTapControlling {
      let log: (String) -> Void
      var isEnabled: Bool = true
      init(log: @escaping (String) -> Void) { self.log = log }
      func install(scope: LockScope) {}
      func remove() { log("tap.remove") }
    }

    let clock = ClockBox()
    let sut = LockManager(
      clock: { clock.now },
      tapController: OrderedTap { callOrder.append($0) },
      presenter: OrderedPresenter { callOrder.append($0) },
      notifier: FakeNotifier(),
      trustChecker: FakeTrustChecker()
    )

    sut.startLock(duration: 60)
    sut.unlock()

    XCTAssertEqual(
      callOrder, ["presenter.dismiss", "tap.remove"],
      "presenter.dismiss must precede tap.remove"
    )
  }

  func testUnlockIsIdempotent() {
    let (sut, presenter, tapController, _) = makeSUT()

    sut.startLock(duration: 60)
    sut.unlock()
    sut.unlock()  // second unlock must be a no-op

    XCTAssertEqual(presenter.dismissCallCount, 1, "dismiss must be called exactly once")
    XCTAssertEqual(tapController.removeCallCount, 1, "remove must be called exactly once")
  }

  // MARK: - Escape combo detector

  func testThreeEscapesWithinWindowUnlocks() {
    let (sut, _, _, _) = makeSUT()
    sut.startLock(duration: 60)

    let t0: TimeInterval = 0
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0))
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.5))
    let unlocked = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 1.0)

    XCTAssertTrue(unlocked)
    XCTAssertEqual(sut.state, .idle)
  }

  func testEscapesTooFarApartDoNotUnlock() {
    let (sut, _, _, _) = makeSUT()
    sut.startLock(duration: 60)

    let t0: TimeInterval = 0
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0))
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.5))
    // Third press arrives 2 s after the second — exceeds the 1.5 s window.
    let unlocked = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.5 + 2.0)

    XCTAssertFalse(unlocked)
    XCTAssertNotEqual(sut.state, .idle)
  }

  func testNonEscapeKeyResetsComboCount() {
    let (sut, _, _, _) = makeSUT()
    sut.startLock(duration: 60)

    let t0: TimeInterval = 0
    _ = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0)  // count = 1
    _ = sut.evaluateEscapeCombo(keyCode: 36, timestamp: t0 + 0.1)  // non-Escape resets
    // Two more Escapes — count restarts from 1, needs one more for unlock.
    _ = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.2)
    let unlocked = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.3)

    XCTAssertFalse(unlocked, "Two post-reset Escapes must not unlock")
  }

  func testEscapeComboIsNoOpWhenIdle() {
    let (sut, _, _, _) = makeSUT()
    // State is .idle — no startLock called.
    let result = sut.evaluateEscapeCombo(keyCode: 53, timestamp: 0)
    XCTAssertFalse(result)
    XCTAssertEqual(sut.state, .idle)
  }

  func testInjectedEscapeIntervalIsHonored() {
    // A 0.5 s window: third press at 1.0 s after second is outside the window.
    let presenter = FakeLockPresenter()
    let tapController = FakeEventTapController()
    let notifier = FakeNotifier()
    let trustChecker = FakeTrustChecker()
    let sut = LockManager(
      tapController: tapController,
      presenter: presenter,
      notifier: notifier,
      trustChecker: trustChecker,
      escapeInterval: { 0.5 }
    )
    sut.startLock(duration: 60)

    let t0: TimeInterval = 0
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0))
    XCTAssertFalse(sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.3))
    // Third press at 1.0 s after second — exceeds the 0.5 s injected window.
    let unlocked = sut.evaluateEscapeCombo(keyCode: 53, timestamp: t0 + 0.3 + 1.0)

    XCTAssertFalse(unlocked, "Third press outside the 0.5 s window must not unlock")
    XCTAssertNotEqual(sut.state, .idle)
  }
}
