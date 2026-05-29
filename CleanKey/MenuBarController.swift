import AppKit
import OSLog
import SwiftUI

/// Owns the NSStatusItem, popover, LockManager, and permission guard.
@MainActor
final class MenuBarController: NSObject {

  private var statusItem: NSStatusItem!
  private var popover: NSPopover!
  private let lockManager: LockManager
  private let tapController: RealEventTapController
  private let settings: LockSettings
  private let permissionGuard: PermissionGuard

  override init() {
    tapController = RealEventTapController()
    lockManager = LockManager(
      tapController: tapController,
      presenter: SilentPresenter(),
      notifier: ConsoleNotifier()
    )
    tapController.lockManager = lockManager
    settings = LockSettings()
    permissionGuard = PermissionGuard(
      trustChecker: RealTrustChecker(),
      openSettings: openAccessibilitySettings
    )
    super.init()
    // Wire the real overlay presenter now that lockManager is fully constructed.
    lockManager.presenter = LockOverlayController(lockManager: lockManager)
    setupStatusItem()
    setupPopover()
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = NSImage(
      systemSymbolName: "keyboard",
      accessibilityDescription: "CleanKey"
    )
    statusItem.button?.action = #selector(statusItemClicked)
    statusItem.button?.target = self
  }

  private func setupPopover() {
    popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = NSHostingController(
      rootView: TimerPickerView(settings: settings) { [weak self] duration in
        self?.startLock(duration: duration)
      }
    )
  }

  @objc private func statusItemClicked() {
    guard permissionGuard.check() == .granted else {
      showPermissionAlert()
      return
    }
    togglePopover()
  }

  private func togglePopover() {
    if popover.isShown {
      popover.performClose(nil)
    } else if let button = statusItem.button {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      popover.contentViewController?.view.window?.makeKey()
    }
  }

  private func startLock(duration: TimeInterval) {
    popover.performClose(nil)
    lockManager.startLock(duration: duration)
  }

  private func showPermissionAlert() {
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText =
      "CleanKey needs Accessibility access to block keyboard and trackpad input. Grant it in System Settings."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
      permissionGuard.requestPermission()
    }
  }
}

// MARK: - Private notifier and silent presenter

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
