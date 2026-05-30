import XCTest

@testable import CleanKey

final class SettingsViewModelTests: XCTestCase {

  private func makeSettings(suiteName: String = #function) -> LockSettings {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return LockSettings(defaults: defaults)
  }

  // MARK: - Initialization

  func testInitReflectsCurrentSettings() {
    var settings = makeSettings()
    settings.lastDuration = 300
    settings.overlayMode = .hud
    settings.trackpadMode = .free
    settings.hudCorner = .topLeft
    settings.launchAtLogin = true

    let sut = SettingsViewModel(settings: settings)

    XCTAssertEqual(sut.sliderPosition, TwoZoneSlider.positionForDuration(300))
    XCTAssertEqual(sut.overlayMode, .hud)
    XCTAssertEqual(sut.trackpadMode, .free)
    XCTAssertEqual(sut.hudCorner, .topLeft)
    XCTAssertTrue(sut.launchAtLogin)
  }

  func testInitDefaultsMatchLockSettingsDefaults() {
    let settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)

    XCTAssertEqual(
      sut.sliderPosition, TwoZoneSlider.positionForDuration(LockSettings.defaultDuration))
    XCTAssertEqual(sut.overlayMode, .blackScreen)
    XCTAssertEqual(sut.trackpadMode, .locked)
    XCTAssertEqual(sut.hudCorner, .bottomRight)
    XCTAssertFalse(sut.launchAtLogin)
  }

  // MARK: - save()

  func testSaveWritesAllFourFields() {
    var settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)

    sut.sliderPosition = TwoZoneSlider.positionForDuration(180)
    sut.overlayMode = .hud
    sut.trackpadMode = .free
    sut.hudCorner = .topRight
    sut.launchAtLogin = true

    sut.save(to: &settings)

    XCTAssertEqual(settings.lastDuration, 180)
    XCTAssertEqual(settings.overlayMode, .hud)
    XCTAssertEqual(settings.trackpadMode, .free)
    XCTAssertEqual(settings.hudCorner, .topRight)
    XCTAssertTrue(settings.launchAtLogin)
  }

  func testSaveAfterSliderDragUpdatesLastDuration() {
    var settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)

    // Drag to step 8 → 45 s
    sut.sliderPosition = 8.0 / 20.0

    sut.save(to: &settings)

    XCTAssertEqual(settings.lastDuration, 45)
  }

  func testSaveMapsAllTwentyOneStepsCorrectly() {
    for stepIndex in 0...20 {
      var settings = makeSettings(suiteName: "step\(stepIndex)")
      let sut = SettingsViewModel(settings: settings)
      let position = Double(stepIndex) / 20.0
      sut.sliderPosition = position
      sut.save(to: &settings)
      let expected = TwoZoneSlider.steps[stepIndex]
      XCTAssertEqual(
        settings.lastDuration, expected,
        "Step \(stepIndex): expected \(expected), got \(settings.lastDuration)")
    }
  }

  // MARK: - Display tab model behaviour

  func testHUDCornerRemainsEditableWhenOverlayModeIsBlackScreen() {
    let settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)

    // Confirm starting in blackScreen mode
    XCTAssertEqual(sut.overlayMode, .blackScreen)

    // The model must not gate hudCorner on overlayMode; assignment must stick
    sut.hudCorner = .topLeft
    XCTAssertEqual(sut.hudCorner, .topLeft)

    sut.hudCorner = .topRight
    XCTAssertEqual(sut.hudCorner, .topRight)

    sut.hudCorner = .bottomLeft
    XCTAssertEqual(sut.hudCorner, .bottomLeft)
  }

  func testSavePersistsOverlayModeAndHUDCorner() {
    var settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)

    sut.overlayMode = .hud
    sut.hudCorner = .topLeft
    sut.save(to: &settings)

    XCTAssertEqual(settings.overlayMode, .hud)
    XCTAssertEqual(settings.hudCorner, .topLeft)

    // Also verify blackScreen + non-default corner is persisted
    var settings2 = makeSettings(suiteName: "testSavePersistsOverlayModeAndHUDCorner2")
    let sut2 = SettingsViewModel(settings: settings2)
    sut2.overlayMode = .blackScreen
    sut2.hudCorner = .bottomLeft
    sut2.save(to: &settings2)

    XCTAssertEqual(settings2.overlayMode, .blackScreen)
    XCTAssertEqual(settings2.hudCorner, .bottomLeft)
  }

  // MARK: - SoundFeedback

  func testInitHydratesSoundFeedbackFromSettings() {
    var settings = makeSettings()
    settings.soundFeedback = false
    let sut = SettingsViewModel(settings: settings)
    XCTAssertFalse(sut.soundFeedback)
  }

  func testInitDefaultSoundFeedbackIsTrue() {
    let settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)
    XCTAssertTrue(sut.soundFeedback)
  }

  func testSaveWritesSoundFeedbackToSettings() {
    var settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)
    sut.soundFeedback = false
    sut.save(to: &settings)
    XCTAssertFalse(settings.soundFeedback)
  }

  // MARK: - EscapeInterval

  func testInitHydratesEscapeIntervalFromSettings() {
    var settings = makeSettings()
    settings.escapeInterval = 2.5
    let sut = SettingsViewModel(settings: settings)
    XCTAssertEqual(sut.escapeInterval, 2.5)
  }

  func testInitDefaultEscapeIntervalIs1Point5() {
    let settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)
    XCTAssertEqual(sut.escapeInterval, LockSettings.escapeIntervalDefault)
  }

  func testSaveWritesEscapeIntervalToSettings() {
    var settings = makeSettings()
    let sut = SettingsViewModel(settings: settings)
    sut.escapeInterval = 3.0
    sut.save(to: &settings)
    XCTAssertEqual(settings.escapeInterval, 3.0)
  }

  // MARK: - cancel()

  func testCancelDiscardsChanges() {
    var settings = makeSettings()
    settings.lastDuration = 120
    settings.overlayMode = .blackScreen
    settings.trackpadMode = .locked

    let sut = SettingsViewModel(settings: settings)

    // Mutate draft
    sut.sliderPosition = TwoZoneSlider.positionForDuration(600)
    sut.overlayMode = .hud
    sut.trackpadMode = .free

    // Cancel — don't save
    sut.cancel()

    // Settings remain unchanged
    XCTAssertEqual(settings.lastDuration, 120)
    XCTAssertEqual(settings.overlayMode, .blackScreen)
    XCTAssertEqual(settings.trackpadMode, .locked)
  }

  func testCancelLeavesLockSettingsUnchanged() {
    var settings = makeSettings()
    settings.lastDuration = 60

    let sut = SettingsViewModel(settings: settings)
    sut.sliderPosition = TwoZoneSlider.positionForDuration(300)
    sut.cancel()

    XCTAssertEqual(settings.lastDuration, 60)
  }
}
