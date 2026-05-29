import XCTest

@testable import CleanKey

final class LockSettingsTests: XCTestCase {

  // Each test uses a fresh in-memory suite so real prefs are never touched.
  private func makeSUT(suiteName: String = #function) -> LockSettings {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return LockSettings(defaults: defaults)
  }

  func testDefaultDurationIs120() {
    let sut = makeSUT()
    XCTAssertEqual(sut.lastDuration, 120)
  }

  func testValueBelowMinimumClampsTo30() {
    var sut = makeSUT()
    sut.lastDuration = 5
    XCTAssertEqual(sut.lastDuration, 30)
  }

  func testValueAboveMaximumClampsTo600() {
    var sut = makeSUT()
    sut.lastDuration = 9999
    XCTAssertEqual(sut.lastDuration, 600)
  }

  func testSaveAndLoadRoundTripsValidValue() {
    let suiteName = "testSaveAndLoadRoundTripsValidValue"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    var sut = LockSettings(defaults: defaults)
    sut.lastDuration = 300
    XCTAssertEqual(sut.lastDuration, 300)

    // Re-create from the same defaults store — simulates app relaunch.
    let sut2 = LockSettings(defaults: defaults)
    XCTAssertEqual(sut2.lastDuration, 300)
  }
}
