import Foundation

/// Whether keep-awake should also prevent the display from sleeping.
public enum KeepAwakeMode: String, CaseIterable, Sendable {
  /// Prevent both display sleep and idle system sleep (default).
  case full
  /// Prevent only idle system sleep; the display can still turn off.
  case systemOnly
}

/// Persists user preferences for the Keep-Awake feature.
/// Inject a `UserDefaults(suiteName:)` instance in tests to avoid touching real prefs.
// @unchecked Sendable is safe: UserDefaults read/write operations are thread-safe,
// and all mutations in the app happen on the main actor.
public struct KeepAwakeSettings: @unchecked Sendable {

  // MARK: - Constants

  /// Allowed duration-cap values in seconds. 0 means no cap (indefinite).
  public static let allowedCaps: [TimeInterval] = [0, 3600, 7200, 14400, 28800, 43200]

  /// A throw-away instance backed by an isolated UserDefaults suite.
  /// Use as the default argument in `SettingsViewModel.init` so that
  /// call-sites that omit `keepAwake:` never touch `UserDefaults.standard`.
  public static let inert = KeepAwakeSettings(
    defaults: UserDefaults(suiteName: "com.cleankey.keepawakesettings.inert")!
  )

  // MARK: - Private

  private let defaults: UserDefaults
  private static let durationCapKey = "keepAwakeDurationCap"
  private static let restoreOnLaunchKey = "keepAwakeRestoreOnLaunch"
  private static let lastActiveStateKey = "keepAwakeLastActiveState"
  private static let modeKey = "keepAwakeMode"

  // MARK: - Init

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - API

  /// Maximum keep-awake duration in seconds. 0 means no cap (indefinite).
  /// Non-allowed values are snapped to the nearest entry in `allowedCaps` on write.
  public var durationCap: TimeInterval {
    get {
      let stored = defaults.double(forKey: Self.durationCapKey)
      // `double(forKey:)` returns 0 when the key is absent — 0 is the valid default.
      return stored
    }
    set {
      defaults.set(Self.clampCap(newValue), forKey: Self.durationCapKey)
    }
  }

  /// Whether keep-awake should re-enable automatically when CleanKey launches.
  /// Defaults to `false`.
  public var restoreOnLaunch: Bool {
    get { defaults.bool(forKey: Self.restoreOnLaunchKey) }
    set { defaults.set(newValue, forKey: Self.restoreOnLaunchKey) }
  }

  /// Tracks whether keep-awake was active when the app last exited.
  /// Written by `KeepAwakeManager` on `enable()` / `disable()`. Defaults to `false`.
  public var lastActiveState: Bool {
    get { defaults.bool(forKey: Self.lastActiveStateKey) }
    set { defaults.set(newValue, forKey: Self.lastActiveStateKey) }
  }

  /// Whether to prevent only system sleep or both system and display sleep. Defaults to `.full`.
  public var mode: KeepAwakeMode {
    get { KeepAwakeMode(rawValue: defaults.string(forKey: Self.modeKey) ?? "") ?? .full }
    set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
  }

  // MARK: - Helpers

  /// Snaps `value` to the nearest entry in `allowedCaps`.
  public static func clampCap(_ value: TimeInterval) -> TimeInterval {
    allowedCaps.min(by: { abs($0 - value) < abs($1 - value) }) ?? 0
  }
}
