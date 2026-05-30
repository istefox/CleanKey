import Foundation

/// Builds the menu item list for the quick-pick lock menu.
/// Pure logic — no AppKit or UI imports.
enum QuickPickMenuViewModel {

  struct MenuItem {
    let duration: TimeInterval
    let label: String
  }

  /// The four always-present presets, in display order.
  static let fixedPresets: [TimeInterval] = [15, 30, 60, 120]

  /// Returns the ordered list of items for the quick-pick menu given `settings`.
  /// A fifth item is appended only when `settings.lastDuration` is not among the
  /// four fixed presets.
  static func menuItems(for settings: LockSettings) -> [MenuItem] {
    var items: [MenuItem] = fixedPresets.map { duration in
      MenuItem(duration: duration, label: formatted(duration))
    }
    let last = settings.lastDuration
    let lastSeconds = Int(last.rounded())
    let fixedSeconds = fixedPresets.map { Int($0.rounded()) }
    if !fixedSeconds.contains(lastSeconds) {
      items.append(MenuItem(duration: last, label: "\(formatted(last)) (default)"))
    }
    return items
  }

  // MARK: - Private

  static func formatted(_ duration: TimeInterval) -> String {
    let total = Int(duration)
    let minutes = total / 60
    let seconds = total % 60
    if minutes == 0 {
      return "\(seconds) s"
    } else if seconds == 0 {
      return "\(minutes) min"
    } else {
      return "\(minutes) min \(seconds) s"
    }
  }
}
