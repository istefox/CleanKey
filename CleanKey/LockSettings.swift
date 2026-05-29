import Foundation

/// Persists user preferences for CleanKey.
/// Inject a `UserDefaults(suiteName:)` instance in tests to avoid touching real prefs.
struct LockSettings {

  // MARK: - Constants

  static let minimumDuration: TimeInterval = 30
  static let maximumDuration: TimeInterval = 600
  static let defaultDuration: TimeInterval = 120

  // MARK: - Private

  private let defaults: UserDefaults
  private static let lastDurationKey = "lastDuration"

  // MARK: - Init

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - API

  /// Last-used lock duration in seconds, clamped to 30–600.
  /// Reads `defaultDuration` (120 s) when no value has been stored yet.
  var lastDuration: TimeInterval {
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

  // MARK: - Helpers

  /// Clamps `value` to the valid duration range. Reused by the slider.
  static func clamp(_ value: TimeInterval) -> TimeInterval {
    min(max(value, minimumDuration), maximumDuration)
  }
}
