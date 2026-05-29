import AppKit
import SwiftUI

/// LockPresenting that shows a fullscreen overlay on every display.
/// Uses screenSaver window level + canJoinAllSpaces so it covers all spaces
/// including Stage Manager layouts.
@MainActor
public final class LockOverlayController: LockPresenting {

  private var windows: [NSWindow] = []
  private weak var lockManager: LockManager?

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

  public func present() {
    buildWindows()
  }

  public func dismiss() {
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
  }

  public func tick(remainingTime: TimeInterval) {
    for window in windows {
      guard let hostingView = window.contentView?.subviews.first as? NSHostingView<CountdownView>
      else { continue }
      hostingView.rootView = CountdownView(remainingTime: remainingTime)
    }
  }

  @objc private func screensChanged() {
    guard !windows.isEmpty else { return }
    dismiss()
    present()
  }

  private func buildWindows() {
    windows.removeAll()
    for screen in NSScreen.screens {
      let window = makeOverlayWindow(for: screen)
      windows.append(window)
      window.orderFrontRegardless()
    }
  }

  private func makeOverlayWindow(for screen: NSScreen) -> NSWindow {
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

    let hostingView = NSHostingView(
      rootView: CountdownView(remainingTime: lockManager?.remainingTime ?? 0)
    )
    hostingView.frame = window.contentView?.bounds ?? screen.frame
    hostingView.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(hostingView)

    return window
  }

}
