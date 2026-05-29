import XCTest

@testable import CleanKey

@MainActor
final class PermissionGuardTests: XCTestCase {

  private func makeSUT(trusted: Bool) -> (sut: PermissionGuard, callCount: CallCounter) {
    let checker = FakeTrustChecker()
    checker.trusted = trusted
    let counter = CallCounter()
    let sut = PermissionGuard(
      trustChecker: checker,
      openSettings: { counter.count += 1 }
    )
    return (sut, counter)
  }

  func testCheckReturnsMissingWhenNotTrusted() {
    let (sut, _) = makeSUT(trusted: false)
    XCTAssertEqual(sut.check(), .missing)
  }

  func testCheckReturnsGrantedWhenTrusted() {
    let (sut, _) = makeSUT(trusted: true)
    XCTAssertEqual(sut.check(), .granted)
  }

  func testRequestPermissionCallsOpenSettingsWhenMissing() {
    let (sut, counter) = makeSUT(trusted: false)
    sut.requestPermission()
    XCTAssertEqual(counter.count, 1, "openSettings must be invoked when permission is missing")
  }

  func testRequestPermissionNotCalledWhenGranted() {
    let (sut, counter) = makeSUT(trusted: true)
    sut.requestPermission()
    XCTAssertEqual(counter.count, 0, "openSettings must NOT be invoked when already granted")
  }
}

// Simple reference-type counter so the escaping closure can mutate it.
final class CallCounter {
  var count = 0
}
