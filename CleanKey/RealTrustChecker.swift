import AppKit
import ApplicationServices

/// Concrete TrustChecking backed by AXIsProcessTrusted().
public final class RealTrustChecker: TrustChecking {
  public init() {}
  public var isTrusted: Bool { AXIsProcessTrusted() }
}

/// Opens System Settings > Privacy & Security > Accessibility.
@MainActor
func openAccessibilitySettings() {
  let url = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
  NSWorkspace.shared.open(url)
}
