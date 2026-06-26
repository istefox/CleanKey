import Foundation

public enum PermissionStatus: Equatable {
  case granted
  case missing
}

/// Gates the app on AXIsProcessTrusted() and guides the user to grant it.
@MainActor
public final class PermissionGuard {

  private let trustChecker: TrustChecking
  private let openSettingsAction: () -> Void

  public init(
    trustChecker: TrustChecking,
    openSettings: @escaping () -> Void
  ) {
    self.trustChecker = trustChecker
    self.openSettingsAction = openSettings
  }

  public func check() -> PermissionStatus {
    trustChecker.isTrusted ? .granted : .missing
  }

  /// Opens System Settings > Privacy > Accessibility.
  public func requestPermission() {
    guard check() == .missing else { return }
    // Register the app in the Accessibility list (and show the system prompt)
    // before opening Settings, so the user lands on a list that contains a
    // CleanKey row to toggle rather than an empty one.
    trustChecker.promptForTrust()
    openSettingsAction()
  }
}
