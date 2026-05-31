import Foundation
import IOKit.ps

// MARK: - Context

/// Context box passed to the C callback via a retained raw pointer.
///
/// Single owner: `RealPowerSourceObserver` retains on `start()` and releases
/// on `stop()`. The C callback only reads the `observer` weak reference and
/// bounces to the main run loop — it never mutates context fields directly.
///
/// @unchecked Sendable is safe: the box is created on the main actor, the weak
/// `observer` reference is only dereferenced inside a `Task { @MainActor in }`,
/// and the box is released on the main actor in `stop()`. The C callback thread
/// only holds the raw pointer transiently via `Unmanaged`.
private final class PowerContext: @unchecked Sendable {
  weak var observer: RealPowerSourceObserver?
  init(observer: RealPowerSourceObserver) {
    self.observer = observer
  }
}

// MARK: - C callback

private func powerSourceCallback(context: UnsafeMutableRawPointer?) {
  guard let rawPtr = context else { return }
  // Retain-balance: takeUnretainedValue does not consume the retain count held
  // by passRetained in start(); the box lives until stop() releases it.
  let ctx = Unmanaged<PowerContext>.fromOpaque(rawPtr).takeUnretainedValue()
  Task { @MainActor in
    ctx.observer?.handlePowerSourceChange()
  }
}

// MARK: - RealPowerSourceObserver

/// Production `PowerSourceObserving`.
///
/// Installs an `IOPSNotification` run-loop source on `CFRunLoopGetMain()` in
/// `.commonModes` so the callback fires even while a menu-tracking run-loop
/// mode is active (ADR-003 D4, plan risk note).
///
/// Memory contract:
///  - `contextPtr` is retained at `start()` and released at `stop()`.
///  - `runLoopSource` is removed from the run loop and invalidated in `stop()`.
///  - Single owner — never copy the context pointer.
@MainActor
public final class RealPowerSourceObserver: PowerSourceObserving {

  // MARK: - State

  private var onChange: ((_ isOnBattery: Bool) -> Void)?
  private var runLoopSource: CFRunLoopSource?
  private var contextPtr: UnsafeMutableRawPointer?

  // MARK: - PowerSourceObserving

  /// Starts observing power source changes.
  ///
  /// Idempotent: calling `start` while already running is a no-op. The
  /// callback fires once each time the power source transitions; the caller
  /// should treat it as an edge notification, not a periodic poll.
  public func start(onChange: @escaping (_ isOnBattery: Bool) -> Void) {
    guard runLoopSource == nil else { return }

    self.onChange = onChange

    let ctx = PowerContext(observer: self)
    let rawPtr = Unmanaged.passRetained(ctx).toOpaque()
    contextPtr = rawPtr

    guard let unmanagedSrc = IOPSNotificationCreateRunLoopSource(powerSourceCallback, rawPtr) else {
      // Allocation failed — release the retained context and bail.
      Unmanaged<PowerContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
      self.onChange = nil
      return
    }

    let src = unmanagedSrc.takeRetainedValue()
    runLoopSource = src
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
  }

  /// Stops observing and releases all resources.
  ///
  /// Idempotent: safe to call when not started.
  public func stop() {
    if let src = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
      CFRunLoopSourceInvalidate(src)
      runLoopSource = nil
    }
    if let rawPtr = contextPtr {
      Unmanaged<PowerContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
    }
    onChange = nil
  }

  // MARK: - Internal

  /// Called on the main actor by the C callback.
  ///
  /// Reads the current power source via `IOPSCopyPowerSourcesInfo` /
  /// `IOPSGetProvidingPowerSourceType` and invokes `onChange(isOnBattery:)`.
  func handlePowerSourceChange() {
    guard let cb = onChange else { return }

    let isOnBattery: Bool
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let type = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as String?
    {
      isOnBattery = (type == kIOPSBatteryPowerValue)
    } else {
      // Cannot determine source; conservatively treat as on AC (no false warning).
      isOnBattery = false
    }

    cb(isOnBattery)
  }
}
