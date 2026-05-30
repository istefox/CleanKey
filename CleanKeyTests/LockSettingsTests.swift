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

  func testValueBelowMinimumClampsToMinimum() {
    var sut = makeSUT()
    sut.lastDuration = 1
    XCTAssertEqual(sut.lastDuration, LockSettings.minimumDuration)
  }

  func testMinimumDurationIs5() {
    XCTAssertEqual(LockSettings.minimumDuration, 5)
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

  // MARK: - EscapeInterval

  func testEscapeIntervalDefaultIs1Point5() {
    let sut = makeSUT()
    XCTAssertEqual(sut.escapeInterval, 1.5)
  }

  func testEscapeIntervalRoundTrip() {
    var sut = makeSUT()
    sut.escapeInterval = 2.0
    XCTAssertEqual(sut.escapeInterval, 2.0)
  }

  func testEscapeIntervalBelowMinimumClampsTo0Point5() {
    var sut = makeSUT()
    sut.escapeInterval = 0.1
    XCTAssertEqual(sut.escapeInterval, LockSettings.escapeIntervalMinimum)
  }

  func testEscapeIntervalAboveMaximumClampsTo3() {
    var sut = makeSUT()
    sut.escapeInterval = 99
    XCTAssertEqual(sut.escapeInterval, LockSettings.escapeIntervalMaximum)
  }

  // MARK: - OverlayMode

  func testOverlayModeDefaultIsBlackScreen() {
    let sut = makeSUT()
    XCTAssertEqual(sut.overlayMode, .blackScreen)
  }

  func testOverlayModeRoundTrip() {
    var sut = makeSUT()
    sut.overlayMode = .hud
    XCTAssertEqual(sut.overlayMode, .hud)
  }

  func testOverlayModeUnknownRawValueFallsBackToDefault() {
    let suiteName = #function
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set("invalid", forKey: "overlayMode")
    let sut = LockSettings(defaults: defaults)
    XCTAssertEqual(sut.overlayMode, .blackScreen)
  }

  // MARK: - TrackpadMode

  func testTrackpadModeDefaultIsLocked() {
    let sut = makeSUT()
    XCTAssertEqual(sut.trackpadMode, .locked)
  }

  func testTrackpadModeRoundTrip() {
    var sut = makeSUT()
    sut.trackpadMode = .free
    XCTAssertEqual(sut.trackpadMode, .free)
  }

  func testTrackpadModeUnknownRawValueFallsBackToDefault() {
    let suiteName = #function
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set("invalid", forKey: "trackpadMode")
    let sut = LockSettings(defaults: defaults)
    XCTAssertEqual(sut.trackpadMode, .locked)
  }

  // MARK: - HUDCorner

  func testHUDCornerDefaultIsBottomRight() {
    let sut = makeSUT()
    XCTAssertEqual(sut.hudCorner, .bottomRight)
  }

  func testHUDCornerRoundTrip() {
    var sut = makeSUT()
    sut.hudCorner = .topLeft
    XCTAssertEqual(sut.hudCorner, .topLeft)
  }

  func testHUDCornerUnknownRawValueFallsBackToDefault() {
    let suiteName = #function
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set("invalid", forKey: "hudCorner")
    let sut = LockSettings(defaults: defaults)
    XCTAssertEqual(sut.hudCorner, .bottomRight)
  }
}
