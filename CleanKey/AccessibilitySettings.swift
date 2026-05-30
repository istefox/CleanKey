import AppKit

/// Opens System Settings > Privacy & Security > Accessibility.
@MainActor
func openAccessibilitySettings() {
  let url = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
  NSWorkspace.shared.open(url)
}
