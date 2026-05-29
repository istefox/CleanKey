import Foundation

/// Injected overlay lifecycle — no AppKit import in LockManager.
@MainActor
public protocol LockPresenting: AnyObject {
  func present()
  func dismiss()
}

/// Injected event-tap lifecycle seam. All calls happen on the main actor.
@MainActor
public protocol EventTapControlling: AnyObject {
  func install()
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
