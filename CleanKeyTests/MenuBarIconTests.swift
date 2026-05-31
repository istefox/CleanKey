import XCTest

@testable import CleanKey

/// Unit-tests for the pure `iconName(locked:awake:)` helper on `MenuBarController`.
/// All four `(Bool, Bool)` combinations must map to the expected asset name (ADR-003 D3).
@MainActor
final class MenuBarIconTests: XCTestCase {

  func testUnlockedNotAwake() {
    XCTAssertEqual(MenuBarController.iconName(locked: false, awake: false), "menubar-unlocked")
  }

  func testLockedNotAwake() {
    XCTAssertEqual(MenuBarController.iconName(locked: true, awake: false), "menubar-locked")
  }

  func testUnlockedAwake() {
    XCTAssertEqual(MenuBarController.iconName(locked: false, awake: true), "menubar-awake")
  }

  func testLockedAndAwake() {
    XCTAssertEqual(MenuBarController.iconName(locked: true, awake: true), "menubar-locked-awake")
  }
}
