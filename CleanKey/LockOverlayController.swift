import AppKit
import SwiftUI

/// LockPresenting that shows either a fullscreen overlay or compact HUD panels
/// on every display, depending on the configured overlay mode.
@MainActor
public final class LockOverlayController: LockPresenting {

  private var windows: [NSWindow] = []
  private weak var lockManager: LockManager?

  private var overlayMode: OverlayMode = .blackScreen
  private var trackpadMode: TrackpadMode = .locked
  private var hudCorner: HUDCorner = .bottomRight

  /// Tracks whether cursor was hidden by present() so dismiss() balances it.
  private var cursorHidden = false

  /// Shared model observed by all CountdownView instances; a single property
  /// mutation propagates to every window without replacing the root view.
  private let countdownModel = CountdownModel()

  public init(lockManager: LockManager) {
    self.lockManager = lockManager
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public func configure(settings: LockSettings) {
    overlayMode = settings.overlayMode
    trackpadMode = settings.trackpadMode
    hudCorner = settings.hudCorner
  }

  public func present() {
    countdownModel.remainingTime = lockManager?.remainingTime ?? 0
    switch overlayMode {
    case .blackScreen:
      buildFullScreenWindows()
      if trackpadMode != .free {
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
        cursorHidden = true
      }
    case .hud:
      buildHUDPanels()
    // Cursor remains visible in HUD mode regardless of trackpad mode.
    }
  }

  public func dismiss() {
    if cursorHidden {
      CGDisplayShowCursor(CGMainDisplayID())
      NSCursor.unhide()
      cursorHidden = false
    }
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
  }

  public func tick(remainingTime: TimeInterval) {
    countdownModel.remainingTime = remainingTime
  }

  @objc private func screensChanged() {
    guard !windows.isEmpty else { return }
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
    switch overlayMode {
    case .blackScreen:
      buildFullScreenWindows()
      if cursorHidden {
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
      }
    case .hud:
      buildHUDPanels()
    }
  }

  // MARK: - Private builders

  private func buildFullScreenWindows() {
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
    for screen in NSScreen.screens {
      let window = makeFullScreenWindow(for: screen)
      windows.append(window)
      window.orderFrontRegardless()
    }
    windows.first?.makeKey()
  }

  private func buildHUDPanels() {
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
    for screen in NSScreen.screens {
      let panel = makeHUDPanel(for: screen)
      windows.append(panel)
      panel.orderFrontRegardless()
    }
  }

  private func makeFullScreenWindow(for screen: NSScreen) -> NSWindow {
    let window = NSWindow(
      contentRect: screen.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.level = .screenSaver
    window.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    window.isOpaque = true
    window.backgroundColor = .black
    window.ignoresMouseEvents = true
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(
      rootView: CountdownView(model: countdownModel)
    )
    return window
  }

  private func makeHUDPanel(for screen: NSScreen) -> NSPanel {
    let panelSize = CGSize(width: 200, height: 80)
    let frame = hudPanelFrame(for: screen.frame, corner: hudCorner, size: panelSize)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = NSColor.black.withAlphaComponent(0.85)
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.hasShadow = true
    panel.contentView = NSHostingView(
      rootView: CountdownView(model: countdownModel)
    )
    return panel
  }
}
