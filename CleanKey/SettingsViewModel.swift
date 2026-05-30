import Foundation
import Observation

/// Draft state for the Settings window. Initialise from LockSettings; call save(to:) or cancel().
@Observable
final class SettingsViewModel {

  var sliderPosition: Double
  var overlayMode: OverlayMode
  var trackpadMode: TrackpadMode
  var hudCorner: HUDCorner
  var escapeInterval: TimeInterval

  init(settings: LockSettings) {
    sliderPosition = TwoZoneSlider.positionForDuration(settings.lastDuration)
    overlayMode = settings.overlayMode
    trackpadMode = settings.trackpadMode
    hudCorner = settings.hudCorner
    escapeInterval = settings.escapeInterval
  }

  /// Writes all draft fields to the provided LockSettings instance.
  func save(to settings: inout LockSettings) {
    settings.lastDuration = TwoZoneSlider.durationForPosition(sliderPosition)
    settings.overlayMode = overlayMode
    settings.trackpadMode = trackpadMode
    settings.hudCorner = hudCorner
    settings.escapeInterval = escapeInterval
  }

  /// Discards the current draft without writing to LockSettings.
  func cancel() {
    // No-op: draft is not persisted until save(to:) is called.
  }
}
