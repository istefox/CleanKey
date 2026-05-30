import Foundation

/// Injected overlay lifecycle — no AppKit import in LockManager.
@MainActor
public protocol LockPresenting: AnyObject {
  func present()
  func dismiss()
  /// Called by LockManager on each watchdog tick while the lock is active.
  /// Default no-op — only overlays that render countdown need to implement it.
  func tick(remainingTime: TimeInterval)
  /// Configures the presenter with user settings before a lock session begins.
  /// Default no-op — conformers that need to apply settings override this.
  func configure(settings: LockSettings)
}

extension LockPresenting {
  public func tick(remainingTime: TimeInterval) {}
  public func configure(settings: LockSettings) {}
}

/// Injected event-tap lifecycle seam. All calls happen on the main actor.
@MainActor
public protocol EventTapControlling: AnyObject {
  func install(trackpadFree: Bool)
  func remove()
  var isEnabled: Bool { get }
}

/// Injected user-notification seam.
public protocol Notifying: AnyObject {
  func post(message: String)
}

/// Injected Accessibility trust check seam.
/// The real implementation calls `AXIsProcessTrusted()`.
public protocol TrustChecking: AnyObject {
  var isTrusted: Bool { get }
}
