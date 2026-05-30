import Foundation

/// The observable state of `LockManager`.
public enum LockState {
  case idle
  /// The keyboard/trackpad tap is active.
  /// - Parameters:
  ///   - endsAt: Wall-clock deadline. Unlock fires when `Date() >= endsAt`.
  ///   - escapeCombo: Running escape-combo tracking state.
  case locked(endsAt: Date, escapeCombo: EscapeComboState)
}

/// Mutable state for the triple-Escape unlock combo.
/// Held inside the locked case so it is cleared automatically on unlock.
public struct EscapeComboState {
  /// Number of consecutive Escape keydowns seen since the last reset.
  public var count: Int = 0
  /// `CFTimeInterval` timestamp of the most recent Escape keydown, or nil.
  public var lastTimestamp: TimeInterval? = nil

  public init() {}
}
