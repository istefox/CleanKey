import AppKit
import OSLog
import SwiftUI

extension Notification.Name {
  static let cleanKeyHotkeyChanged = Notification.Name("cleanKeyHotkeyChanged")
}

/// Owns the NSStatusItem, LockManager, KeepAwakeManager, and permission guard.
@MainActor
final class MenuBarController: NSObject {

  private var statusItem: NSStatusItem!
  private let lockManager: LockManager
  private let tapController: RealEventTapController
  private let settings: LockSettings
  private let permissionGuard: PermissionGuard
  private let keepAwakeManager: KeepAwakeManager
  private let hotkeyRegistrar: HotkeyRegistering
  private var hotkeyObserverToken: (any NSObjectProtocol)?
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
    ),
    hotkeyRegistrar: HotkeyRegistering = CarbonHotkeyRegistrar()
  ) {
    self.keepAwakeManager = keepAwakeManager
    self.hotkeyRegistrar = hotkeyRegistrar
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
    setupHotkey()
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

  private func updateMenuBarIcon() {
    if !isLocked { statusItem.button?.title = "" }
    let img: NSImage?
    switch (isLocked, isAwake) {
    case (false, false): img = keyboardIcon(lockBadge: false, sun: nil)
    case (true, false): img = keyboardIcon(lockBadge: true, sun: nil)
    case (false, true): img = keyboardIcon(lockBadge: false, sun: .bottomRight)
    case (true, true): img = keyboardIcon(lockBadge: true, sun: .topRight)
    }
    if let img {
      statusItem.button?.image = img
    }
  }

  private enum SunCorner { case bottomRight, topRight }

  /// Keyboard base with an optional lock badge and/or a quarter-sun drawn from a corner.
  /// Locked+awake: lock at bottom-right, sun peeking from top-right.
  private func keyboardIcon(lockBadge: Bool, sun: SunCorner?) -> NSImage? {
    let kbCfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    guard
      let kb = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
        .withSymbolConfiguration(kbCfg)
    else { return nil }

    guard lockBadge || sun != nil else {
      kb.isTemplate = true
      return kb
    }

    let size = kb.size
    let result = NSImage(size: size, flipped: false) { _ in
      kb.draw(in: NSRect(origin: .zero, size: size))

      if lockBadge {
        let cfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        if let lockImg = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
          .withSymbolConfiguration(cfg)
        {
          lockImg.draw(
            in: NSRect(
              x: size.width - lockImg.size.width, y: 0,
              width: lockImg.size.width, height: lockImg.size.height))
        }
      }

      if let pos = sun, let ctx = NSGraphicsContext.current?.cgContext {
        self.drawQuarterSun(ctx: ctx, canvasSize: size, position: pos)
      }
      return true
    }
    result.isTemplate = true
    return result
  }

  /// Draws a filled quarter-circle arc with rays from a canvas corner.
  /// The arc body + rays act as a "peek-in" sun badge for the keep-awake state.
  private func drawQuarterSun(ctx: CGContext, canvasSize: NSSize, position: SunCorner) {
    let radius: CGFloat = 8
    let rayLength: CGFloat = 4
    let gap: CGFloat = 2
    // Transparent moat punched into the keyboard layer around the sun silhouette.
    let halo: CGFloat = 1.0

    let corner: CGPoint
    let startAngle: CGFloat
    let endAngle: CGFloat
    let rayAngles: [CGFloat]

    switch position {
    case .bottomRight:
      corner = CGPoint(x: canvasSize.width, y: 0)
      startAngle = .pi / 2
      endAngle = .pi
      rayAngles = [.pi / 2, 2 * .pi / 3, 5 * .pi / 6, .pi]
    case .topRight:
      corner = CGPoint(x: canvasSize.width, y: canvasSize.height)
      startAngle = .pi
      endAngle = 3 * .pi / 2
      rayAngles = [.pi, 7 * .pi / 6, 4 * .pi / 3, 3 * .pi / 2]
    }

    // Pass 1: erase a halo-sized silhouette from the keyboard layer.
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.beginPath()
    ctx.move(to: corner)
    ctx.addArc(
      center: corner, radius: radius + halo,
      startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.closePath()
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setLineWidth(1.5 + 2 * halo)
    ctx.setLineCap(.round)
    for angle in rayAngles {
      let s = CGPoint(
        x: corner.x + (radius + gap) * cos(angle),
        y: corner.y + (radius + gap) * sin(angle))
      let e = CGPoint(
        x: corner.x + (radius + gap + rayLength) * cos(angle),
        y: corner.y + (radius + gap + rayLength) * sin(angle))
      ctx.beginPath()
      ctx.move(to: s)
      ctx.addLine(to: e)
      ctx.strokePath()
    }
    ctx.restoreGState()

    // Pass 2: draw the actual sun on top.
    ctx.saveGState()
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.beginPath()
    ctx.move(to: corner)
    ctx.addArc(
      center: corner, radius: radius,
      startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.closePath()
    ctx.fillPath()
    ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    for angle in rayAngles {
      let s = CGPoint(
        x: corner.x + (radius + gap) * cos(angle),
        y: corner.y + (radius + gap) * sin(angle))
      let e = CGPoint(
        x: corner.x + (radius + gap + rayLength) * cos(angle),
        y: corner.y + (radius + gap + rayLength) * sin(angle))
      ctx.beginPath()
      ctx.move(to: s)
      ctx.addLine(to: e)
      ctx.strokePath()
    }
    ctx.restoreGState()
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

  // MARK: - Global hotkey

  private func setupHotkey() {
    hotkeyRegistrar.onTrigger = { [weak self] in self?.handleHotkeyTriggered() }
    registerHotkeyFromSettings()
    hotkeyObserverToken = NotificationCenter.default.addObserver(
      forName: .cleanKeyHotkeyChanged, object: nil, queue: .main
    ) { [weak self] _ in
      self?.registerHotkeyFromSettings()
    }
  }

  // deinit intentionally omitted: MenuBarController is a process-lifetime singleton.
  // hotkeyObserverToken uses [weak self], so the registered block is a no-op after
  // deallocation. Both the token and the Carbon registration are reclaimed by the OS
  // on process exit. Swift 6 nonisolated-deinit restrictions make explicit cleanup
  // of @MainActor properties and non-Sendable tokens unsafe without workarounds.

  private func registerHotkeyFromSettings() {
    if let binding = settings.hotkeyBinding {
      hotkeyRegistrar.register(keyCode: binding.keyCode, modifiers: binding.modifiers)
    } else {
      hotkeyRegistrar.unregister()
    }
  }

  private func handleHotkeyTriggered() {
    guard permissionGuard.check() == .granted else {
      showPermissionAlert()
      return
    }
    if isLocked {
      lockManager.extendLock(by: settings.lastDuration)
    } else {
      startLock(duration: settings.lastDuration)
    }
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
  func createAssertions(reason: String, mode: KeepAwakeMode) -> Bool { false }
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
