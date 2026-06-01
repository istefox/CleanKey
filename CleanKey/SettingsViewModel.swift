import Foundation
import Observation

/// Draft state for the Settings window. Initialise from LockSettings; call save(to:) or cancel().
@Observable
final class SettingsViewModel {

  // MARK: - Lock fields

  var sliderPosition: Double
  var overlayMode: OverlayMode
  var lockScope: LockScope
  var hudCorner: HUDCorner
  var escapeInterval: TimeInterval
  var launchAtLogin: Bool
  var soundFeedback: Bool

  // MARK: - Keep-Awake fields

  var keepAwakeDurationCap: TimeInterval
  var keepAwakeRestoreOnLaunch: Bool
  var keepAwakeMode: KeepAwakeMode

  // MARK: - Init

  init(settings: LockSettings, keepAwake: KeepAwakeSettings = .inert) {
    sliderPosition = TwoZoneSlider.positionForDuration(settings.lastDuration)
    overlayMode = settings.overlayMode
    lockScope = settings.lockScope
    hudCorner = settings.hudCorner
    escapeInterval = settings.escapeInterval
    launchAtLogin = settings.launchAtLogin
    soundFeedback = settings.soundFeedback
    keepAwakeDurationCap = keepAwake.durationCap
    keepAwakeRestoreOnLaunch = keepAwake.restoreOnLaunch
    keepAwakeMode = keepAwake.mode
  }

  // MARK: - Save

  /// Writes all lock draft fields to the provided LockSettings instance.
  /// Does NOT touch KeepAwakeSettings — call saveKeepAwake(to:) separately.
  func save(to settings: inout LockSettings) {
    settings.lastDuration = TwoZoneSlider.durationForPosition(sliderPosition)
    settings.overlayMode = overlayMode
    settings.lockScope = lockScope
    settings.hudCorner = hudCorner
    settings.escapeInterval = escapeInterval
    settings.launchAtLogin = launchAtLogin
    settings.soundFeedback = soundFeedback
  }

  /// Writes keep-awake draft fields to the provided KeepAwakeSettings instance.
  /// Does NOT touch LockSettings — call save(to:) separately for lock fields.
  func saveKeepAwake(to keepAwake: inout KeepAwakeSettings) {
    keepAwake.durationCap = keepAwakeDurationCap
    keepAwake.restoreOnLaunch = keepAwakeRestoreOnLaunch
    keepAwake.mode = keepAwakeMode
  }

  // MARK: - Cancel

  /// Discards the current draft without writing to any settings.
  func cancel() {
    // No-op: draft is not persisted until save(to:) / saveKeepAwake(to:) are called.
  }
}
