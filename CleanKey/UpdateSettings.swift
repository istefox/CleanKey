import Foundation

public enum UpdateCheckFrequency: String, CaseIterable, Sendable {
  case daily
  case weekly
  case onLaunch
  case never
}

/// Persists user preferences for the auto-update feature.
/// Inject a `UserDefaults(suiteName:)` instance in tests to avoid touching real prefs.
// @unchecked Sendable is safe: UserDefaults read/write operations are thread-safe,
// and all mutations in the app happen on the main actor.
public struct UpdateSettings: @unchecked Sendable {

  // MARK: - Constants

  /// A throw-away instance backed by an isolated UserDefaults suite.
  /// Use as the default argument in `SettingsViewModel.init` so that
  /// call-sites that omit `updates:` never touch `UserDefaults.standard`.
  public static let inert = UpdateSettings(
    defaults: UserDefaults(suiteName: "com.cleankey.updatesettings.inert")!
  )

  // MARK: - Private

  private let defaults: UserDefaults
  private static let frequencyKey = "updateCheckFrequency"
  private static let lastCheckDateKey = "updateLastCheckDate"

  // MARK: - Init

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - API

  /// How often to automatically check for updates. Defaults to `.daily`.
  public var frequency: UpdateCheckFrequency {
    get { UpdateCheckFrequency(rawValue: defaults.string(forKey: Self.frequencyKey) ?? "") ?? .daily }
    set { defaults.set(newValue.rawValue, forKey: Self.frequencyKey) }
  }

  /// When the last update check was performed. `nil` means never checked.
  public var lastCheckDate: Date? {
    get { defaults.object(forKey: Self.lastCheckDateKey) as? Date }
    set {
      if let date = newValue {
        defaults.set(date, forKey: Self.lastCheckDateKey)
      } else {
        defaults.removeObject(forKey: Self.lastCheckDateKey)
      }
    }
  }
}
