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

  // MARK: - Cursor-visibility gating (smoke)
  // LockOverlayController.present() hides the cursor iff lockScope.trackpadBlocked == true.
  // These tests verify the predicate for all three scopes.

  func testCursorHiddenWhenScopeIsAll() {
    XCTAssertTrue(
      LockScope.all.trackpadBlocked,
      "scope=all must block trackpad so cursor is hidden during lock")
  }

  func testCursorHiddenWhenScopeIsTrackpadOnly() {
    XCTAssertTrue(
      LockScope.trackpadOnly.trackpadBlocked,
      "scope=trackpadOnly must block trackpad so cursor is hidden during lock")
  }

  func testCursorVisibleWhenScopeIsKeyboardOnly() {
    XCTAssertFalse(
      LockScope.keyboardOnly.trackpadBlocked,
      "scope=keyboardOnly must NOT block trackpad so cursor stays visible during lock")
  }
}
