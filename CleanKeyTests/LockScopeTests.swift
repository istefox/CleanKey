import XCTest

@testable import CleanKey

@MainActor
final class LockScopeTests: XCTestCase {

  func testStartLockWithScopeAllCallsInstallScopeAll() {
    let tapController = FakeEventTapController()
    let sut = LockManager(
      tapController: tapController,
      presenter: FakeLockPresenter(),
      notifier: FakeNotifier(),
      lockScope: { .all }
    )

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.lastInstallScope, .all)
  }

  func testStartLockWithScopeKeyboardOnlyCallsInstallScopeKeyboardOnly() {
    let tapController = FakeEventTapController()
    let sut = LockManager(
      tapController: tapController,
      presenter: FakeLockPresenter(),
      notifier: FakeNotifier(),
      lockScope: { .keyboardOnly }
    )

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.lastInstallScope, .keyboardOnly)
  }

  func testStartLockWithScopeTrackpadOnlyCallsInstallScopeTrackpadOnly() {
    let tapController = FakeEventTapController()
    let sut = LockManager(
      tapController: tapController,
      presenter: FakeLockPresenter(),
      notifier: FakeNotifier(),
      lockScope: { .trackpadOnly }
    )

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.lastInstallScope, .trackpadOnly)
  }
}
