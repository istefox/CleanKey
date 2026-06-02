import Carbon
import Foundation

// MARK: - Context

/// Passed to the Carbon event handler via userData.
/// Single owner: allocated at register(), released at unregister().
private final class HotkeyContext: @unchecked Sendable {
  weak var registrar: CarbonHotkeyRegistrar?
}

// MARK: - C event handler

private func carbonHotkeyHandler(
  _ nextHandler: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let rawPtr = userData else { return OSStatus(eventNotHandledErr) }
  let ctx = Unmanaged<HotkeyContext>.fromOpaque(rawPtr).takeUnretainedValue()
  DispatchQueue.main.async {
    ctx.registrar?.handleFired()
  }
  return noErr
}

// MARK: - CarbonHotkeyRegistrar

/// Production `HotkeyRegistering` built on `RegisterEventHotKey`.
/// Mirrors the `Unmanaged` context-pointer pattern used in `RealEventTapController`.
@MainActor
public final class CarbonHotkeyRegistrar: HotkeyRegistering {

  public var onTrigger: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?
  private var contextPtr: UnsafeMutableRawPointer?

  private static let hotkeyID = EventHotKeyID(signature: 0x434B_5948 /* CKHK */, id: 1)

  public init() {}

  @discardableResult
  public func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
    unregister()

    let ctx = HotkeyContext()
    ctx.registrar = self
    let rawPtr = Unmanaged.passRetained(ctx).toOpaque()
    contextPtr = rawPtr

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    var handler: EventHandlerRef?
    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      carbonHotkeyHandler,
      1,
      &spec,
      rawPtr,
      &handler
    )
    guard installStatus == noErr else {
      Unmanaged<HotkeyContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
      return false
    }
    handlerRef = handler

    var ref: EventHotKeyRef?
    let registerStatus = RegisterEventHotKey(
      keyCode, modifiers, Self.hotkeyID,
      GetApplicationEventTarget(), 0, &ref
    )
    guard registerStatus == noErr else {
      if let h = handlerRef { RemoveEventHandler(h) }
      handlerRef = nil
      Unmanaged<HotkeyContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
      return false
    }
    hotKeyRef = ref
    return true
  }

  public func unregister() {
    if let ref = hotKeyRef {
      UnregisterEventHotKey(ref)
      hotKeyRef = nil
    }
    if let h = handlerRef {
      RemoveEventHandler(h)
      handlerRef = nil
    }
    if let rawPtr = contextPtr {
      Unmanaged<HotkeyContext>.fromOpaque(rawPtr).release()
      contextPtr = nil
    }
  }

  fileprivate func handleFired() {
    onTrigger?()
  }
}
