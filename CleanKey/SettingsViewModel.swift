import Foundation
import Observation

/// Draft state for the Settings window. Initialise from LockSettings; call save(to:) or cancel().
@Observable
final class SettingsViewModel {

  var sliderPosition: Double
  var overlayMode: OverlayMode
  var lockScope: LockScope
  var hudCorner: HUDCorner
  var escapeInterval: TimeInterval
  var launchAtLogin: Bool
  var soundFeedback: Bool

  init(settings: LockSettings) {
    sliderPosition = TwoZoneSlider.positionForDuration(settings.lastDuration)
    overlayMode = settings.overlayMode
    lockScope = settings.lockScope
    hudCorner = settings.hudCorner
    escapeInterval = settings.escapeInterval
    launchAtLogin = settings.launchAtLogin
    soundFeedback = settings.soundFeedback
  }

  /// Writes all draft fields to the provided LockSettings instance.
  func save(to settings: inout LockSettings) {
    settings.lastDuration = TwoZoneSlider.durationForPosition(sliderPosition)
    settings.overlayMode = overlayMode
    settings.lockScope = lockScope
    settings.hudCorner = hudCorner
    settings.escapeInterval = escapeInterval
    settings.launchAtLogin = launchAtLogin
    settings.soundFeedback = soundFeedback
  }

  /// Discards the current draft without writing to LockSettings.
  func cancel() {
    // No-op: draft is not persisted until save(to:) is called.
  }
}
