import ApplicationServices

/// Concrete TrustChecking backed by AXIsProcessTrusted().
public final class RealTrustChecker: TrustChecking {
  public init() {}

  /// Silent check — never prompts. Safe for passive gating and the watchdog.
  public var isTrusted: Bool { AXIsProcessTrusted() }

  /// Prompting check. `AXIsProcessTrustedWithOptions` with the prompt option
  /// shows the system Accessibility dialog and registers the app in the
  /// Accessibility list, so a fresh install (or a cleared grant) leaves a
  /// CleanKey row the user can actually toggle, instead of an empty list.
  @discardableResult
  public func promptForTrust() -> Bool {
    // Use the literal key rather than the imported `kAXTrustedCheckOptionPrompt`
    // global: under Swift 6 strict concurrency that CFString `var` is flagged as
    // shared mutable state. The literal is the exact value the constant holds.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
