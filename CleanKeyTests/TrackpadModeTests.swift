import XCTest

@testable import CleanKey

@MainActor
final class TrackpadModeTests: XCTestCase {

  func testStartLockWithTrackpadFreeCallsInstallTrackpadFreeTrue() {
    let tapController = FakeEventTapController()
    let sut = LockManager(
      tapController: tapController,
      presenter: FakeLockPresenter(),
      notifier: FakeNotifier(),
      trackpadMode: { .free }
    )

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.lastInstallTrackpadFree, true)
  }

  func testStartLockWithTrackpadLockedCallsInstallTrackpadFreeFalse() {
    let tapController = FakeEventTapController()
    let sut = LockManager(
      tapController: tapController,
      presenter: FakeLockPresenter(),
      notifier: FakeNotifier(),
      trackpadMode: { .locked }
    )

    sut.startLock(duration: 60)

    XCTAssertEqual(tapController.lastInstallTrackpadFree, false)
  }
}
