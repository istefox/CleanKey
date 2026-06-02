import Foundation

/// Injected seam for Carbon global hotkey registration.
/// Keeps Carbon out of the `MenuBarController` unit-test path.
@MainActor
public protocol HotkeyRegistering: AnyObject {
  /// Called on the main actor when the registered hotkey fires.
  var onTrigger: (() -> Void)? { get set }
  /// Registers the hotkey. Returns `false` if registration fails.
  @discardableResult
  func register(keyCode: UInt32, modifiers: UInt32) -> Bool
  /// Unregisters the current hotkey. No-op if none is registered.
  func unregister()
}
