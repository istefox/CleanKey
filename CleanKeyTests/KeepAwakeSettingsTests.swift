import XCTest

@testable import CleanKey

final class KeepAwakeSettingsTests: XCTestCase {

  // Each test uses a fresh in-memory suite so real prefs are never touched.
  private func makeSUT(suiteName: String = #function) -> KeepAwakeSettings {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return KeepAwakeSettings(defaults: defaults)
  }

  // MARK: - Defaults

  func testDurationCapDefaultIsZero() {
    let sut = makeSUT()
    XCTAssertEqual(sut.durationCap, 0)
  }

  func testRestoreOnLaunchDefaultIsFalse() {
    let sut = makeSUT()
    XCTAssertFalse(sut.restoreOnLaunch)
  }

  func testLastActiveStateDefaultIsFalse() {
    let sut = makeSUT()
    XCTAssertFalse(sut.lastActiveState)
  }

  // MARK: - Round-trip

  func testRoundTripAllFields() {
    let suiteName = "testRoundTripAllFields"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    var sut = KeepAwakeSettings(defaults: defaults)
    sut.durationCap = 7200
    sut.restoreOnLaunch = true
    sut.lastActiveState = true

    // Re-create from the same defaults store — simulates app relaunch.
    let sut2 = KeepAwakeSettings(defaults: defaults)
    XCTAssertEqual(sut2.durationCap, 7200)
    XCTAssertTrue(sut2.restoreOnLaunch)
    XCTAssertTrue(sut2.lastActiveState)
  }

  // MARK: - clampCap

  func testClampCapSnapsOffListValueToNearest() {
    // 5000 is between allowedCaps[1] (3600) and allowedCaps[2] (7200).
    // Nearest is 3600 (delta 1400) vs 7200 (delta 2200).
    let clamped = KeepAwakeSettings.clampCap(5000)
    let nearest = KeepAwakeSettings.allowedCaps.min(by: { abs($0 - 5000) < abs($1 - 5000) })!
    XCTAssertEqual(clamped, nearest)
    // Verify it referenced allowedCaps, not a literal.
    XCTAssertTrue(KeepAwakeSettings.allowedCaps.contains(clamped))
  }

  func testClampCapReturnsZeroForZero() {
    XCTAssertEqual(KeepAwakeSettings.clampCap(0), 0)
  }

  func testClampCapAllowedValuesAreIdempotent() {
    for cap in KeepAwakeSettings.allowedCaps {
      XCTAssertEqual(
        KeepAwakeSettings.clampCap(cap), cap,
        "clampCap(\(cap)) should be idempotent")
    }
  }

  func testSettingNonAllowedDurationCapReadsBackClamped() {
    var sut = makeSUT()
    sut.durationCap = 5000  // not in allowedCaps
    let nearest = KeepAwakeSettings.allowedCaps.min(by: { abs($0 - 5000) < abs($1 - 5000) })!
    XCTAssertEqual(sut.durationCap, nearest)
    XCTAssertTrue(KeepAwakeSettings.allowedCaps.contains(sut.durationCap))
  }
}
