import AppKit
import Carbon
import SwiftUI

// MARK: - NSView backing

final class RecorderNSView: NSView {
  var settings: LockSettings
  var onBindingChanged: (() -> Void)?
  private var isRecording = false

  init(settings: LockSettings) {
    self.settings = settings
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override var acceptsFirstResponder: Bool { true }

  override func resignFirstResponder() -> Bool {
    isRecording = false
    needsDisplay = true
    return super.resignFirstResponder()
  }

  override func mouseDown(with event: NSEvent) {
    guard !isRecording else { return }
    isRecording = true
    window?.makeFirstResponder(self)
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { return }

    // Escape cancels recording.
    if event.keyCode == 53 {
      isRecording = false
      needsDisplay = true
      return
    }

    // Require at least one modifier key.
    let nsFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard
      nsFlags.contains(.command) || nsFlags.contains(.control)
        || nsFlags.contains(.option) || nsFlags.contains(.shift)
    else { return }

    let carbonMods = carbonModifiers(from: nsFlags)
    settings.hotkeyBinding = HotkeyBinding(
      keyCode: UInt32(event.keyCode),
      modifiers: carbonMods
    )
    isRecording = false
    // Write back to @Binding and notify before needsDisplay so SwiftUI state
    // is consistent before the next draw cycle.
    onBindingChanged?()
    NotificationCenter.default.post(name: .cleanKeyHotkeyChanged, object: nil)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let label: String
    if isRecording {
      label = "Type shortcut…"
    } else if let b = settings.hotkeyBinding {
      label = b.displayString
    } else {
      label = "Click to record"
    }

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
      .foregroundColor: isRecording ? NSColor.systemBlue : NSColor.labelColor,
    ]
    let str = NSAttributedString(string: label, attributes: attrs)
    let size = str.size()
    let origin = CGPoint(
      x: (bounds.width - size.width) / 2,
      y: (bounds.height - size.height) / 2
    )
    str.draw(at: origin)
  }

  // MARK: - Modifier conversion

  private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask: UInt32 = 0
    if flags.contains(.command) { mask |= UInt32(cmdKey) }
    if flags.contains(.shift) { mask |= UInt32(shiftKey) }
    if flags.contains(.option) { mask |= UInt32(optionKey) }
    if flags.contains(.control) { mask |= UInt32(controlKey) }
    return mask
  }
}

// MARK: - SwiftUI wrapper

struct HotkeyRecorderView: NSViewRepresentable {
  @Binding var settings: LockSettings

  func makeNSView(context: Context) -> RecorderNSView {
    let v = RecorderNSView(settings: settings)
    v.onBindingChanged = { [weak v] in
      if let s = v?.settings { settings = s }
    }
    return v
  }

  func updateNSView(_ nsView: RecorderNSView, context: Context) {
    nsView.settings = settings
    nsView.needsDisplay = true
  }
}
