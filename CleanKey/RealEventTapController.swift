import CoreGraphics
import Foundation

// MARK: - Context

/// Memory-managed context allocated at tap install and freed at tap remove.
/// Passed to the C callback via the `userInfo` pointer.
///
/// Single owner — `RealEventTapController` allocates and frees.
/// Never copy the raw pointer.
// @unchecked Sendable is safe: TapContext is created on the main actor,
// the `controller` weak reference is only read on the main actor (inside
// DispatchQueue.main.async), and the object is freed on the main actor in
// remove(). The callback thread only reads the pointer via Unmanaged; it
// never mutates TapContext fields directly.
private final class TapContext: @unchecked Sendable {
  weak var controller: RealEventTapController?
  init(controller: RealEventTapController) { self.controller = controller }
}

// MARK: - C callback

private func eventTapCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

  guard let rawPtr = userInfo else { return Unmanaged.passRetained(event) }

  let ctx = Unmanaged<TapContext>.fromOpaque(rawPtr).takeUnretainedValue()

  if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
    // Watchdog will detect isEnabled == false on next tick; no extra action needed.
    return nil
  }

  if type == .keyDown {
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    // CGEventTimestamp is mach absolute time; divide by 1e9 for seconds.
    let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
    DispatchQueue.main.async {
      ctx.controller?.routeKeyDown(keyCode: keyCode, timestamp: timestamp)
    }
  }

  return nil  // drop all events while tap is active
}

// MARK: - RealEventTapController

/// Production `EventTapControlling`.
///
/// Installs a session-level CGEventTap that drops all keyboard and
/// pointing-device events, and routes Escape keydowns to LockManager's
/// combo evaluator.
///
/// Memory contract (ADR Decision 6):
///  - TapContext is retained at install(), released at remove().
///  - Raw pointer is passed to CGEvent.tapCreate as userInfo.
///  - Single owner: do not copy the pointer.
@MainActor
public final class RealEventTapController: EventTapControlling {

  // Weak reference so the controller can forward Escape keydowns.
  public weak var lockManager: LockManager?

  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var contextPtr: UnsafeMutableRawPointer?

  public var isEnabled: Bool {
    guard let tap else { return false }
    return CGEvent.tapIsEnabled(tap: tap)
  }

  public func install() {
    guard tap == nil else { return }

    let ctx = TapContext(controller: self)
    let rawPtr = Unmanaged.passRetained(ctx).toOpaque()
    contextPtr = rawPtr

    let keyMask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.flagsChanged.rawValue)

    let pointingMask: CGEventMask =
      (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.leftMouseUp.rawValue)
      | (1 << CGEventType.leftMouseDragged.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue)
      | (1 << CGEventType.rightMouseUp.rawValue)
      | (1 << CGEventType.rightMouseDragged.rawValue)
      | (1 << CGEventType.otherMouseDown.rawValue)
      | (1 << CGEventType.otherMouseUp.rawValue)
      | (1 << CGEventType.otherMouseDragged.rawValue)
      | (1 << CGEventType.mouseMoved.rawValue)
      | (1 << CGEventType.scrollWheel.rawValue)

    let tapDisabledMask: CGEventMask =
      (1 << CGEventType.tapDisabledByUserInput.rawValue)
      | (1 << CGEventType.tapDisabledByTimeout.rawValue)

    let eventMask = keyMask | pointingMask | tapDisabledMask

    guard
      let newTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: eventTapCallback,
        userInfo: rawPtr
      )
    else {
      Unmanaged<TapContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
      return
    }

    tap = newTap

    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
    runLoopSource = src
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
  }

  public func remove() {
    defer {
      if let rawPtr = contextPtr {
        Unmanaged<TapContext>.fromOpaque(rawPtr).release()
        contextPtr = nil
      }
    }

    guard let currentTap = tap else { return }
    CGEvent.tapEnable(tap: currentTap, enable: false)

    if let src = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
      runLoopSource = nil
    }

    CFMachPortInvalidate(currentTap)
    tap = nil
  }

  func routeKeyDown(keyCode: CGKeyCode, timestamp: TimeInterval) {
    lockManager?.evaluateEscapeCombo(keyCode: keyCode, timestamp: timestamp)
  }
}
