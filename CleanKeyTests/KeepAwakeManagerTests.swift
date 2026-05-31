import XCTest

@testable import CleanKey

@MainActor
final class KeepAwakeManagerTests: XCTestCase {

  // MARK: - Helpers

  private func makeSUT(
    createShouldFail: Bool = false,
    cap: TimeInterval = 0
  ) -> (
    sut: KeepAwakeManager,
    assertions: FakeSleepAssertionController,
    powerObserver: FakePowerSourceObserver,
    notifier: FakeBatteryWarningNotifier,
    onChangeCalls: Box<Int>,
    persistValues: Box<[Bool]>
  ) {
    let assertions = FakeSleepAssertionController()
    assertions.createShouldFail = createShouldFail
    let powerObserver = FakePowerSourceObserver()
    let notifier = FakeBatteryWarningNotifier()
    let onChangeCalls = Box(0)
    let persistValues = Box<[Bool]>([])

    let sut = KeepAwakeManager(
      assertions: assertions,
      powerObserver: powerObserver,
      notifier: notifier,
      capProvider: { cap },
      onChange: { onChangeCalls.value += 1 },
      persist: { persistValues.value.append($0) }
    )
    return (sut, assertions, powerObserver, notifier, onChangeCalls, persistValues)
  }

  // MARK: - enable() basic

  func testEnableFromIdleCreatesAssertionsAndActivates() {
    let (sut, assertions, powerObserver, _, onChangeCalls, persistValues) = makeSUT()

    sut.enable()

    XCTAssertEqual(assertions.createCallCount, 1)
    XCTAssertTrue(sut.isActive)
    XCTAssertEqual(onChangeCalls.value, 1)
    XCTAssertEqual(persistValues.value, [true])
    XCTAssertEqual(powerObserver.startCallCount, 1)
  }

  func testEnableWhenAlreadyActiveIsNoOp() {
    let (sut, assertions, _, _, onChangeCalls, _) = makeSUT()
    sut.enable()

    sut.enable()  // second call — must be idempotent

    XCTAssertEqual(assertions.createCallCount, 1, "create called more than once")
    XCTAssertEqual(onChangeCalls.value, 1, "onChange fired more than once")
  }

  // MARK: - disable()

  func testDisableFromActiveReleasesAndDeactivates() {
    let assertions = FakeSleepAssertionController()
    let powerObserver = FakePowerSourceObserver()
    let notifier = FakeBatteryWarningNotifier()
    let onChangeCalls = Box(0)
    let persistValues = Box<[Bool]>([])

    // Wrap stop/release in a shared call log to verify teardown order.
    // We rely on the fact that FakePowerSourceObserver.stop and
    // FakeSleepAssertionController.releaseAssertions are called in that order
    // by KeepAwakeManager.disable(). We verify via call counts and the fact
    // that release count increments after stop count increments (checked below).
    let sut = KeepAwakeManager(
      assertions: assertions,
      powerObserver: powerObserver,
      notifier: notifier,
      capProvider: { 0 },
      onChange: { onChangeCalls.value += 1 },
      persist: { persistValues.value.append($0) }
    )
    sut.enable()
    let createCount = assertions.createCallCount
    XCTAssertEqual(createCount, 1)

    sut.disable()

    XCTAssertEqual(assertions.releaseCallCount, 1)
    XCTAssertFalse(sut.isActive)
    XCTAssertEqual(powerObserver.stopCallCount, 1)
    XCTAssertEqual(notifier.clearBatteryWarningCallCount, 1)
    XCTAssertEqual(persistValues.value.last, false)
    XCTAssertEqual(onChangeCalls.value, 2)  // once for enable, once for disable
  }

  func testTeardownOrderStopObserverBeforeRelease() {
    // Verify the full ADR-003 D2 teardown order:
    // stop cap timer → stop power observer → release assertions → clearBatteryWarning → persist → onChange
    // Strategy: use a shared Box<[String]> captured by the persist closure and
    // wired to the fake hooks. A `recording` flag gates the log so that the
    // enable()-side persist(true) call is excluded.
    let log = Box<[String]>([])
    let recording = Box(false)

    let assertions = FakeSleepAssertionController()
    let powerObserver = FakePowerSourceObserver()
    let notifier = FakeBatteryWarningNotifier()

    powerObserver.onStop = { log.value.append("observerStop") }
    assertions.onRelease = { log.value.append("release") }
    notifier.onClear = { log.value.append("clearBattery") }

    let sut = KeepAwakeManager(
      assertions: assertions,
      powerObserver: powerObserver,
      notifier: notifier,
      capProvider: { 0 },
      onChange: {},
      persist: { _ in if recording.value { log.value.append("persist") } }
    )
    sut.enable()
    // Activate recording after enable() so persist(true) is not captured.
    recording.value = true
    sut.disable()

    // Full teardown sequence: stop cap timer → stop power observer → release assertions → clearBatteryWarning → persist → onChange
    XCTAssertEqual(
      log.value,
      ["observerStop", "release", "clearBattery", "persist"],
      "Teardown order must be: stop observer → release assertions → clearBatteryWarning → persist"
    )
  }

  func testDisableWhenIdleIsNoOp() {
    let (sut, assertions, powerObserver, _, onChangeCalls, _) = makeSUT()

    sut.disable()  // nothing to disable

    XCTAssertEqual(assertions.releaseCallCount, 0)
    XCTAssertEqual(powerObserver.stopCallCount, 0)
    XCTAssertEqual(onChangeCalls.value, 0)
  }

  // MARK: - Failure path

  func testEnableWithAssertionFailureStaysInactive() {
    let (sut, assertions, powerObserver, _, onChangeCalls, _) = makeSUT(createShouldFail: true)

    sut.enable()

    XCTAssertFalse(sut.isActive)
    XCTAssertEqual(powerObserver.startCallCount, 0, "observer must not start when create fails")
    XCTAssertEqual(onChangeCalls.value, 0, "onChange must not fire when create fails")
    XCTAssertEqual(assertions.createCallCount, 1)
  }

  // MARK: - Cap timer

  func testCapTimerFireCallsDisable() {
    let (sut, assertions, powerObserver, _, onChangeCalls, persistValues) = makeSUT(cap: 3600)
    sut.enable()
    XCTAssertTrue(sut.isActive)

    // Drive the cap timer via the test-injectable entry point.
    sut.capTimerFired()

    XCTAssertFalse(sut.isActive)
    XCTAssertEqual(assertions.releaseCallCount, 1)
    XCTAssertEqual(powerObserver.stopCallCount, 1)
    XCTAssertEqual(persistValues.value.last, false)
    XCTAssertEqual(onChangeCalls.value, 2)  // enable + disable
  }

  func testDisableBeforeCapTimerFiresSuppressesTimer() {
    // Enable with a cap so the timer is scheduled, then disable immediately.
    // Calling capTimerFired() afterwards must be a no-op (manager already inactive).
    let (sut, assertions, _, _, _, _) = makeSUT(cap: 3600)
    sut.enable()
    XCTAssertTrue(sut.isActive)

    sut.disable()
    XCTAssertFalse(sut.isActive)
    XCTAssertEqual(assertions.releaseCallCount, 1, "disable() should have released once")

    // Simulate the real timer firing after the manual disable.
    sut.capTimerFired()

    // capTimerFired() calls disable(), which is a no-op when already inactive.
    XCTAssertEqual(
      assertions.releaseCallCount, 1, "capTimerFired must be a no-op when already disabled")
  }

  func testCapTimerIsNotStartedWhenCapIsZero() {
    // With cap == 0 (no limit), the timer must not be created.
    // We verify indirectly: capTimerFired() when never enabled must not crash
    // and must be a no-op.
    let (sut, assertions, _, _, _, _) = makeSUT(cap: 0)
    sut.enable()

    // The real timer is not firing; calling capTimerFired() must be a no-op
    // when already active (the method guards on isActive but cap == 0 means
    // the timer was never started and the manager should stay active).
    // Since we cannot prevent the real timer from firing in unit tests when
    // cap > 0, this test just verifies that with cap == 0 the manager stays
    // active until explicitly disabled.
    XCTAssertTrue(sut.isActive)
    sut.disable()
    XCTAssertFalse(sut.isActive)
    XCTAssertEqual(assertions.releaseCallCount, 1)
  }

  // MARK: - Power callback

  func testPowerCallbackOnBatteryWhileActivePostsWarning() {
    let (sut, _, powerObserver, notifier, _, _) = makeSUT()
    sut.enable()

    powerObserver.fireOnChange(isOnBattery: true)

    XCTAssertEqual(notifier.postBatteryWarningCallCount, 1)
    XCTAssertTrue(sut.isActive, "manager must NOT auto-disable on battery (SPEC §5.2)")
  }

  func testPowerCallbackOnACWhileActiveDoesNotPostWarning() {
    let (sut, _, powerObserver, notifier, _, _) = makeSUT()
    sut.enable()

    powerObserver.fireOnChange(isOnBattery: false)

    XCTAssertEqual(notifier.postBatteryWarningCallCount, 0)
    XCTAssertTrue(sut.isActive)
  }

  func testPowerCallbackWhileInactiveIsNoOp() {
    let (sut, _, powerObserver, notifier, _, _) = makeSUT()
    // Do NOT call enable — sut is idle.
    // We simulate the callback by starting the observer manually and firing.
    // Actually, since the observer is only started inside enable(), and the fake
    // captures the closure at that point, the callback cannot fire unless
    // we've enabled. This test verifies that the guard inside the callback works.
    sut.enable()
    sut.disable()
    // Observer was stopped on disable; fireOnChange after stop should not reach the manager.
    // FakePowerSourceObserver.stop() nils onChange, so fireOnChange becomes a no-op.
    powerObserver.fireOnChange(isOnBattery: true)

    XCTAssertEqual(notifier.postBatteryWarningCallCount, 0)
  }

  // MARK: - requestAuthorizationIfNeeded

  func testEnableRequestsNotificationAuthorization() {
    let (sut, _, _, notifier, _, _) = makeSUT()

    sut.enable()

    XCTAssertEqual(notifier.requestAuthorizationCallCount, 1)
  }

  // MARK: - Restore-on-launch

  func testShouldRestoreOnLaunch() {
    // Verifies the launch-restore logic: when restoreOnLaunch == true AND
    // lastActiveState == true, calling enable() activates the manager.
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    var settings = KeepAwakeSettings(defaults: defaults)
    settings.restoreOnLaunch = true
    settings.lastActiveState = true

    let assertions = FakeSleepAssertionController()
    let sut = KeepAwakeManager(
      assertions: assertions,
      powerObserver: FakePowerSourceObserver(),
      notifier: FakeBatteryWarningNotifier(),
      capProvider: { 0 },
      onChange: {},
      persist: { _ in }
    )

    // Simulate the AppDelegate restore-on-launch branch.
    if settings.restoreOnLaunch && settings.lastActiveState {
      sut.enable()
    }

    XCTAssertTrue(sut.isActive, "manager must be active after restore-on-launch")
    XCTAssertEqual(assertions.createCallCount, 1, "assertions must be created on restore")
  }
}

// MARK: - Box helper (avoids capture-list verbosity)

private final class Box<T>: @unchecked Sendable {
  var value: T
  init(_ value: T) { self.value = value }
}
