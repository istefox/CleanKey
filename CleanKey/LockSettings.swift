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

  public static let escapeIntervalMinimum: TimeInterval = 0.5
  public static let escapeIntervalMaximum: TimeInterval = 3.0
  public static let escapeIntervalDefault: TimeInterval = 1.5

  // MARK: - Private

  private let defaults: UserDefaults
  private static let lastDurationKey = "lastDuration"
  private static let overlayModeKey = "overlayMode"
  private static let trackpadModeKey = "trackpadMode"
  private static let hudCornerKey = "hudCorner"
  private static let escapeIntervalKey = "escapeInterval"
  private static let launchAtLoginKey = "launchAtLogin"
  private static let soundFeedbackDisabledKey = "soundFeedbackDisabled"

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

  /// Maximum inter-press interval for the triple-Escape emergency unlock, in seconds.
  /// Clamped to 0.5–3.0 s. Defaults to 1.5 s.
  public var escapeInterval: TimeInterval {
    get {
      let stored = defaults.double(forKey: Self.escapeIntervalKey)
      guard stored > 0 else { return Self.escapeIntervalDefault }
      return Self.clampEscapeInterval(stored)
    }
    set {
      defaults.set(Self.clampEscapeInterval(newValue), forKey: Self.escapeIntervalKey)
    }
  }

  /// Whether CleanKey registers as a login item on reboot. Defaults to `false`.
  public var launchAtLogin: Bool {
    get { defaults.bool(forKey: Self.launchAtLoginKey) }
    set { defaults.set(newValue, forKey: Self.launchAtLoginKey) }
  }

  /// Whether lock/unlock events play a system sound. Defaults to `true` (ON).
  /// Stored as the inverse so the absent-key case reads as enabled.
  public var soundFeedback: Bool {
    get { !defaults.bool(forKey: Self.soundFeedbackDisabledKey) }
    set { defaults.set(!newValue, forKey: Self.soundFeedbackDisabledKey) }
  }

  // MARK: - Helpers

  /// Clamps `value` to the valid duration range. Reused by the slider.
  public static func clamp(_ value: TimeInterval) -> TimeInterval {
    min(max(value, minimumDuration), maximumDuration)
  }

  public static func clampEscapeInterval(_ value: TimeInterval) -> TimeInterval {
    min(max(value, escapeIntervalMinimum), escapeIntervalMaximum)
  }
}
