import AppKit
import SwiftUI

/// Owns the Settings window. Single-instance; AppDelegate holds the strong reference.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

  private var window: NSWindow?
  private var settings: LockSettings
  private let launchAtLogin: LaunchAtLoginControlling

  init(settings: LockSettings, launchAtLogin: LaunchAtLoginControlling = LaunchAtLoginManager()) {
    self.settings = settings
    self.launchAtLogin = launchAtLogin
  }

  /// Shows the Settings window, or brings it to front if already visible.
  /// Re-initialises the view model from current persisted values on each call.
  func showOrFocus() {
    if let existing = window, existing.isVisible {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    window?.close()
    window = nil

    let viewModel = SettingsViewModel(settings: settings)

    let settingsView = SettingsView(
      viewModel: viewModel,
      onSave: { [weak self] in
        guard let self else { return }
        viewModel.save(to: &self.settings)
        self.launchAtLogin.apply(self.settings.launchAtLogin)
        self.window?.close()
      },
      onCancel: { [weak self] in
        self?.window?.close()
      }
    )

    let hosting = NSHostingController(rootView: settingsView)

    let win = NSWindow(contentViewController: hosting)
    win.title = "CleanKey Settings"
    win.isReleasedWhenClosed = false
    win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    win.level = .floating
    win.setContentSize(NSSize(width: 520, height: 520))
    win.center()
    win.delegate = self
    win.makeKeyAndOrderFront(nil)
    window = win
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }
}
