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
  let trackpadFree: Bool
  init(controller: RealEventTapController, trackpadFree: Bool) {
    self.controller = controller
    self.trackpadFree = trackpadFree
  }
}

// MARK: - C callback

private func eventTapCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

  guard let rawPtr = userInfo else { return Unmanaged.passUnretained(event) }

  let ctx = Unmanaged<TapContext>.fromOpaque(rawPtr).takeUnretainedValue()

  if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
    // Watchdog will detect isEnabled == false on next tick; no extra action needed.
    return nil
  }

  // In trackpad-free mode, pass through all pointing-device and gesture events.
  if ctx.trackpadFree {
    switch type {
    case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged,
      .mouseMoved, .scrollWheel:
      return Unmanaged.passUnretained(event)
    default:
      // Gesture events (raw 18–20, 29–32) and system events (raw 14).
      let raw = type.rawValue
      if raw == 18 || raw == 19 || raw == 20
        || raw == 29 || raw == 30 || raw == 31 || raw == 32
        || raw == 14
      {
        return Unmanaged.passUnretained(event)
      }
    }
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

  public func install(trackpadFree: Bool) {
    guard tap == nil else { return }

    let ctx = TapContext(controller: self, trackpadFree: trackpadFree)
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

    // Raw 14 = kCGEventSystemDefined: media keys — brightness, volume, eject, Exposé.
    // CGEventType does not expose this case in Swift; raw value used directly.
    let systemMask: CGEventMask = (1 << 14)

    // Multi-touch trackpad gesture events. The public CGEventType enum does not
    // expose these, so raw values are used (mirror NSEvent.EventType):
    //   18 rotate · 19 beginGesture · 20 endGesture
    //   29 gesture (undocumented — 3/4-finger swipes for Mission Control/Exposé)
    //   30 magnify · 31 swipe · 32 smartMagnify
    let gestureMask: CGEventMask =
      (1 << 18) | (1 << 19) | (1 << 20)
      | (1 << 29) | (1 << 30) | (1 << 31) | (1 << 32)

    let eventMask = keyMask | pointingMask | tapDisabledMask | systemMask | gestureMask

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
    guard let currentTap = tap else { return }
    defer {
      if let rawPtr = contextPtr {
        Unmanaged<TapContext>.fromOpaque(rawPtr).release()
        contextPtr = nil
      }
    }

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
