import AppKit
import OSLog
import SwiftUI

/// Owns the NSStatusItem, LockManager, and permission guard.
@MainActor
final class MenuBarController: NSObject {

  private var statusItem: NSStatusItem!
  private let lockManager: LockManager
  private let tapController: RealEventTapController
  private let settings: LockSettings
  private let permissionGuard: PermissionGuard
  weak var settingsWindowController: SettingsWindowController?

  init(
    settings: LockSettings = LockSettings(),
    settingsWindowController: SettingsWindowController? = nil
  ) {
    tapController = RealEventTapController()
    lockManager = LockManager(
      tapController: tapController,
      presenter: SilentPresenter(),
      notifier: ConsoleNotifier(),
      trustChecker: RealTrustChecker(),
      trackpadMode: { [settings] in settings.trackpadMode }
    )
    tapController.lockManager = lockManager
    self.settings = settings
    permissionGuard = PermissionGuard(
      trustChecker: RealTrustChecker(),
      openSettings: openAccessibilitySettings
    )
    super.init()
    self.settingsWindowController = settingsWindowController
    let overlay = LockOverlayController(lockManager: lockManager)
    lockManager.presenter = PresenterProxy(
      real: overlay,
      onPresent: { [weak self] in
        self?.setMenuBarIcon(locked: true)
      },
      onDismiss: { [weak self] in
        self?.setMenuBarIcon(locked: false)
      })
    setupStatusItem()
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.isVisible = true
    statusItem.button?.title = "⌨"
    setMenuBarIcon(locked: false)
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.target = self
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func setMenuBarIcon(locked: Bool) {
    let name = locked ? "menubar-locked" : "menubar-unlocked"
    if let img = NSImage(named: name) {
      img.isTemplate = true
      statusItem.button?.image = img
    } else if let img = NSImage(
      systemSymbolName: locked ? "lock" : "keyboard",
      accessibilityDescription: "CleanKey")
    {
      statusItem.button?.image = img
    }
  }

  @objc private func statusItemClicked() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showContextMenu()
      return
    }
    guard permissionGuard.check() == .granted else {
      showPermissionAlert()
      return
    }
    showQuickPickMenu()
  }

  private func showQuickPickMenu() {
    let menu = NSMenu()
    for item in QuickPickMenuViewModel.menuItems(for: settings) {
      let menuItem = NSMenuItem(
        title: item.label,
        action: #selector(quickPickItemSelected(_:)),
        keyEquivalent: ""
      )
      menuItem.target = self
      menuItem.representedObject = item.duration as AnyObject
      menu.addItem(menuItem)
    }
    guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }

  @objc private func quickPickItemSelected(_ sender: NSMenuItem) {
    guard let duration = sender.representedObject as? TimeInterval else { return }
    startLock(duration: duration)
  }

  private func showContextMenu() {
    let menu = NSMenu()
    let settingsItem = NSMenuItem(
      title: "Settings…",
      action: #selector(openSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(settingsItem)
    menu.addItem(.separator())
    let quitItem = NSMenuItem(
      title: "Quit CleanKey",
      action: #selector(quitApp),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)
    guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }

  @objc private func openSettings() {
    settingsWindowController?.showOrFocus()
  }

  @objc private func quitApp() {
    NSApplication.shared.terminate(nil)
  }

  private func startLock(duration: TimeInterval) {
    lockManager.presenter.configure(settings: settings)
    lockManager.startLock(duration: duration)
  }

  private func showPermissionAlert() {
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.makeKeyAndOrderFront(nil)

    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText =
      "CleanKey needs Accessibility access to block keyboard and trackpad input. Grant it in System Settings."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    let response = alert.runModal()
    panel.close()

    if response == .alertFirstButtonReturn {
      permissionGuard.requestPermission()
    }
  }
}

// MARK: - Private helpers

private final class PresenterProxy: LockPresenting {
  private let real: any LockPresenting
  private let onPresent: () -> Void
  private let onDismiss: () -> Void

  init(real: any LockPresenting, onPresent: @escaping () -> Void, onDismiss: @escaping () -> Void) {
    self.real = real
    self.onPresent = onPresent
    self.onDismiss = onDismiss
  }

  func present() {
    real.present()
    onPresent()
  }
  func dismiss() {
    real.dismiss()
    onDismiss()
  }
  func tick(remainingTime: TimeInterval) { real.tick(remainingTime: remainingTime) }
  func configure(settings: LockSettings) { real.configure(settings: settings) }
}

private final class SilentPresenter: LockPresenting {
  func present() {}
  func dismiss() {}
}

private final class ConsoleNotifier: Notifying {
  private let logger = Logger(subsystem: "it.stefer.CleanKey", category: "lock")
  func post(message: String) {
    logger.info("\(message, privacy: .public)")
  }
}

// A borderless NSPanel whose canBecomeKey is overridden to true so that
// NSAlert.runModal() gets a real key-window anchor in LSUIElement apps.
private final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
}
