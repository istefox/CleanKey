import XCTest

@testable import CleanKey

@MainActor
final class PermissionGuardTests: XCTestCase {

  private func makeSUT(trusted: Bool)
    -> (sut: PermissionGuard, callCount: CallCounter, checker: FakeTrustChecker)
  {
    let checker = FakeTrustChecker()
    checker.trusted = trusted
    let counter = CallCounter()
    let sut = PermissionGuard(
      trustChecker: checker,
      openSettings: { counter.count += 1 }
    )
    return (sut, counter, checker)
  }

  func testCheckReturnsMissingWhenNotTrusted() {
    let (sut, _, _) = makeSUT(trusted: false)
    XCTAssertEqual(sut.check(), .missing)
  }

  func testCheckReturnsGrantedWhenTrusted() {
    let (sut, _, _) = makeSUT(trusted: true)
    XCTAssertEqual(sut.check(), .granted)
  }

  func testRequestPermissionCallsOpenSettingsWhenMissing() {
    let (sut, counter, _) = makeSUT(trusted: false)
    sut.requestPermission()
    XCTAssertEqual(counter.count, 1, "openSettings must be invoked when permission is missing")
  }

  func testRequestPermissionNotCalledWhenGranted() {
    let (sut, counter, _) = makeSUT(trusted: true)
    sut.requestPermission()
    XCTAssertEqual(counter.count, 0, "openSettings must NOT be invoked when already granted")
  }

  func testRequestPermissionPromptsForTrustWhenMissing() {
    let (sut, _, checker) = makeSUT(trusted: false)
    sut.requestPermission()
    XCTAssertEqual(
      checker.promptForTrustCallCount, 1,
      "promptForTrust must register the app in the Accessibility list when permission is missing")
  }

  func testRequestPermissionDoesNotPromptWhenGranted() {
    let (sut, _, checker) = makeSUT(trusted: true)
    sut.requestPermission()
    XCTAssertEqual(
      checker.promptForTrustCallCount, 0,
      "promptForTrust must NOT be invoked when permission is already granted")
  }
}

// Simple reference-type counter so the escaping closure can mutate it.
final class CallCounter {
  var count = 0
}
