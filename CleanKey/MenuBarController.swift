import AppKit
import OSLog
import SwiftUI

/// Owns the NSStatusItem, LockManager, KeepAwakeManager, and permission guard.
@MainActor
final class MenuBarController: NSObject {

  private var statusItem: NSStatusItem!
  private let lockManager: LockManager
  private let tapController: RealEventTapController
  private let settings: LockSettings
  private let permissionGuard: PermissionGuard
  private let keepAwakeManager: KeepAwakeManager
  weak var settingsWindowController: SettingsWindowController?

  // 4-state icon flags (ADR-003 D3)
  private var isLocked = false
  private var isAwake = false

  init(
    settings: LockSettings = LockSettings(),
    settingsWindowController: SettingsWindowController? = nil,
    keepAwakeManager: KeepAwakeManager = KeepAwakeManager(
      assertions: NoOpSleepAssertionController(),
      powerObserver: NoOpPowerSourceObserver(),
      notifier: NoOpBatteryWarningNotifier()
    )
  ) {
    self.keepAwakeManager = keepAwakeManager
    tapController = RealEventTapController()
    lockManager = LockManager(
      tapController: tapController,
      presenter: SilentPresenter(),
      notifier: ConsoleNotifier(),
      trustChecker: RealTrustChecker(),
      lockScope: { [settings] in settings.lockScope },
      escapeInterval: { [settings] in settings.escapeInterval }
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
    let sound = SoundFeedbackPresenter(real: overlay)
    lockManager.presenter = PresenterProxy(
      real: sound,
      onPresent: { [weak self] in
        self?.isLocked = true
        self?.updateMenuBarIcon()
      },
      onDismiss: { [weak self] in
        self?.isLocked = false
        self?.updateMenuBarIcon()
      },
      onTick: { [weak self] remaining in
        self?.setMenuBarTitle(remaining: remaining)
      })
    keepAwakeManager.onChange = { [weak self] in
      guard let self else { return }
      self.isAwake = self.keepAwakeManager.isActive
      self.updateMenuBarIcon()
    }
    setupStatusItem()
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.isVisible = true
    statusItem.button?.title = "⌨"
    updateMenuBarIcon()
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.target = self
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func setMenuBarTitle(remaining: TimeInterval) {
    let total = max(0, Int(remaining))
    let m = total / 60
    let s = total % 60
    statusItem.button?.title = String(format: "%d:%02d", m, s)
  }

  /// Derives the icon asset name from the two independent state flags (ADR-003 D3).
  static func iconName(locked: Bool, awake: Bool) -> String {
    switch (locked, awake) {
    case (false, false): return "menubar-unlocked"
    case (true, false): return "menubar-locked"
    case (false, true): return "menubar-awake"
    case (true, true): return "menubar-locked-awake"
    }
  }

  private func updateMenuBarIcon() {
    // Clear countdown title when not locked (preserve it while locked).
    if !isLocked { statusItem.button?.title = "" }
    let name = MenuBarController.iconName(locked: isLocked, awake: isAwake)
    if let img = NSImage(named: name) {
      img.isTemplate = true
      statusItem.button?.image = img
    } else {
      // SF Symbol fallbacks when asset art is not yet available.
      let symbolName: String
      switch (isLocked, isAwake) {
      case (false, false): symbolName = "keyboard"
      case (true, false): symbolName = "lock"
      case (false, true): symbolName = "sun.max"
      case (true, true): symbolName = "lock.circle"
      }
      if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CleanKey") {
        statusItem.button?.image = img
      }
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
    // Keep Awake toggle item (placed above Settings per ADR-003 D3).
    let keepAwakeTitle = isAwake ? "Disable Keep Awake" : "Enable Keep Awake"
    let keepAwakeAction: Selector =
      isAwake ? #selector(disableKeepAwake) : #selector(enableKeepAwake)
    let keepAwakeItem = NSMenuItem(
      title: keepAwakeTitle,
      action: keepAwakeAction,
      keyEquivalent: ""
    )
    keepAwakeItem.target = self
    menu.addItem(keepAwakeItem)
    menu.addItem(.separator())
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

  @objc private func enableKeepAwake() {
    keepAwakeManager.enable()
  }

  @objc private func disableKeepAwake() {
    keepAwakeManager.disable()
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
  private let onTick: (TimeInterval) -> Void

  init(
    real: any LockPresenting,
    onPresent: @escaping () -> Void,
    onDismiss: @escaping () -> Void,
    onTick: @escaping (TimeInterval) -> Void
  ) {
    self.real = real
    self.onPresent = onPresent
    self.onDismiss = onDismiss
    self.onTick = onTick
  }

  func present() {
    real.present()
    onPresent()
  }
  func dismiss() {
    real.dismiss()
    onDismiss()
  }
  func tick(remainingTime: TimeInterval) {
    real.tick(remainingTime: remainingTime)
    onTick(remainingTime)
  }
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

// MARK: - No-op keep-awake stubs (used only in the default MenuBarController init)
// Task 7 replaces the default with real implementations constructed by AppDelegate.

@MainActor
private final class NoOpSleepAssertionController: SleepAssertionControlling {
  var isHeld: Bool { false }
  func createAssertions(reason: String) -> Bool { false }
  func releaseAssertions() {}
}

@MainActor
private final class NoOpPowerSourceObserver: PowerSourceObserving {
  func start(onChange: @escaping (Bool) -> Void) {}
  func stop() {}
}

@MainActor
private final class NoOpBatteryWarningNotifier: BatteryWarningNotifying {
  func requestAuthorizationIfNeeded() {}
  func postBatteryWarning() {}
  func clearBatteryWarning() {}
}
