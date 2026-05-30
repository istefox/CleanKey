import Foundation

public enum OverlayMode: String {
  case blackScreen
  case hud
}

public enum TrackpadMode: String {
  case locked
  case free
}

public enum HUDCorner: String {
  case topLeft
  case topRight
  case bottomRight
  case bottomLeft
}

/// Persists user preferences for CleanKey.
/// Inject a `UserDefaults(suiteName:)` instance in tests to avoid touching real prefs.
// @unchecked Sendable is safe: UserDefaults read/write operations are thread-safe,
// and all mutations in the app happen on the main actor.
public struct LockSettings: @unchecked Sendable {

  // MARK: - Constants

  public static let minimumDuration: TimeInterval = 5
  public static let maximumDuration: TimeInterval = 600
  public static let defaultDuration: TimeInterval = 120

  // MARK: - Private

  private let defaults: UserDefaults
  private static let lastDurationKey = "lastDuration"
  private static let overlayModeKey = "overlayMode"
  private static let trackpadModeKey = "trackpadMode"
  private static let hudCornerKey = "hudCorner"

  // MARK: - Init

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - API

  /// Last-used lock duration in seconds, clamped to 5–600.
  /// Reads `defaultDuration` (120 s) when no value has been stored yet.
  public var lastDuration: TimeInterval {
    get {
      let stored = defaults.double(forKey: Self.lastDurationKey)
      // `double(forKey:)` returns 0 when the key is absent.
      guard stored > 0 else { return Self.defaultDuration }
      return Self.clamp(stored)
    }
    set {
      defaults.set(Self.clamp(newValue), forKey: Self.lastDurationKey)
    }
  }

  /// Overlay presentation mode. Defaults to `.blackScreen`.
  public var overlayMode: OverlayMode {
    get {
      guard let raw = defaults.string(forKey: Self.overlayModeKey),
        let value = OverlayMode(rawValue: raw)
      else { return .blackScreen }
      return value
    }
    set {
      defaults.set(newValue.rawValue, forKey: Self.overlayModeKey)
    }
  }

  /// Trackpad behavior during a lock. Defaults to `.locked`.
  public var trackpadMode: TrackpadMode {
    get {
      guard let raw = defaults.string(forKey: Self.trackpadModeKey),
        let value = TrackpadMode(rawValue: raw)
      else { return .locked }
      return value
    }
    set {
      defaults.set(newValue.rawValue, forKey: Self.trackpadModeKey)
    }
  }

  /// Screen corner for HUD overlay panels. Defaults to `.bottomRight`.
  public var hudCorner: HUDCorner {
    get {
      guard let raw = defaults.string(forKey: Self.hudCornerKey),
        let value = HUDCorner(rawValue: raw)
      else { return .bottomRight }
      return value
    }
    set {
      defaults.set(newValue.rawValue, forKey: Self.hudCornerKey)
    }
  }

  // MARK: - Helpers

  /// Clamps `value` to the valid duration range. Reused by the slider.
  public static func clamp(_ value: TimeInterval) -> TimeInterval {
    min(max(value, minimumDuration), maximumDuration)
  }
}
