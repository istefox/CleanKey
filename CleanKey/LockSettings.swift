import Carbon
import Foundation

// MARK: - HotkeyBinding

/// Carbon key code + modifier mask pair for a registered global hotkey.
public struct HotkeyBinding: Equatable {
  public let keyCode: UInt32
  public let modifiers: UInt32

  public init(keyCode: UInt32, modifiers: UInt32) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Human-readable label built from Carbon modifier bits + a key-name table.
  public var displayString: String {
    var parts: [String] = []
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
    parts.append(Self.keyName(for: keyCode))
    return parts.joined()
  }

  private static func keyName(for code: UInt32) -> String {
    let table: [UInt32: String] = [
      0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
      8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
      16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
      23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
      30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
      38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
      45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
      51: "⌫", 53: "⎋", 117: "⌦", 118: "F4", 119: "F6", 120: "F2",
      121: "F8", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
    return table[code] ?? "(\(code))"
  }
}

// MARK: -

public enum OverlayMode: String {
  case blackScreen
  case hud
}

public enum LockScope: String {
  case all
  case keyboardOnly
  case trackpadOnly

  var keyboardBlocked: Bool { self != .trackpadOnly }
  var trackpadBlocked: Bool { self != .keyboardOnly }
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
  private static let lockScopeKey = "lockScope"
  private static let trackpadModeKey = "trackpadMode"  // legacy migration only
  private static let hudCornerKey = "hudCorner"
  private static let escapeIntervalKey = "escapeInterval"
  private static let launchAtLoginKey = "launchAtLogin"
  private static let soundFeedbackDisabledKey = "soundFeedbackDisabled"
  private static let hotkeyCodeKey = "hotkeyKeyCode"
  private static let hotkeyModifiersKey = "hotkeyModifiers"
  private static let hotkeyEnabledKey = "hotkeyEnabled"

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

  /// Which inputs are blocked during a lock. Defaults to `.all`.
  /// Migrates the legacy `trackpadMode` key on first read if `lockScope` is absent.
  public var lockScope: LockScope {
    get {
      if let raw = defaults.string(forKey: Self.lockScopeKey),
        let value = LockScope(rawValue: raw)
      {
        return value
      }
      // Legacy migration: map old trackpadMode to the nearest LockScope.
      if let legacyRaw = defaults.string(forKey: Self.trackpadModeKey) {
        return legacyRaw == "free" ? .keyboardOnly : .all
      }
      return .all
    }
    set {
      defaults.set(newValue.rawValue, forKey: Self.lockScopeKey)
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

  /// Persisted global hotkey binding. `nil` means no shortcut is set.
  /// Live-persisted (bypasses the SettingsViewModel draft flow — hotkey
  /// recording happens outside the Save/Cancel window lifecycle).
  public var hotkeyBinding: HotkeyBinding? {
    get {
      guard defaults.bool(forKey: Self.hotkeyEnabledKey) else { return nil }
      let code = UInt32(defaults.integer(forKey: Self.hotkeyCodeKey))
      let mods = UInt32(defaults.integer(forKey: Self.hotkeyModifiersKey))
      return HotkeyBinding(keyCode: code, modifiers: mods)
    }
    set {
      if let b = newValue {
        defaults.set(true, forKey: Self.hotkeyEnabledKey)
        defaults.set(Int(b.keyCode), forKey: Self.hotkeyCodeKey)
        defaults.set(Int(b.modifiers), forKey: Self.hotkeyModifiersKey)
      } else {
        defaults.removeObject(forKey: Self.hotkeyEnabledKey)
        defaults.removeObject(forKey: Self.hotkeyCodeKey)
        defaults.removeObject(forKey: Self.hotkeyModifiersKey)
      }
    }
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
