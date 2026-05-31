import Foundation
import UserNotifications

// MARK: - Constants

private enum NotificationID {
  static let category = "KEEP_AWAKE_BATTERY_WARNING"
  static let disableAction = "KEEP_AWAKE_DISABLE"
  static let requestID = "com.cleankey.keepawake.battery-warning"
}

// MARK: - KeepAwakeNotifier

/// Production `BatteryWarningNotifying`.
///
/// Wraps `UNUserNotificationCenter` to post a user-visible battery banner
/// when keep-awake is active on battery. The banner has a "Disable" action
/// that calls back to `onDisableRequested` — wired by `AppDelegate` to
/// `KeepAwakeManager.disable()`.
///
/// Authorization is requested lazily on the first `requestAuthorizationIfNeeded()`
/// call (which `KeepAwakeManager.enable()` triggers). If the user denies,
/// `postBatteryWarning()` is a silent no-op (SPEC §7).
///
/// This type is `@MainActor` because all callers (`KeepAwakeManager`) run on the
/// main actor. `UNUserNotificationCenterDelegate` methods are marked `nonisolated`
/// because the system calls them on an arbitrary background thread; they hop back
/// to the main actor via `Task { @MainActor in }` where state mutations are needed.
@MainActor
public final class KeepAwakeNotifier: NSObject,
  BatteryWarningNotifying, UNUserNotificationCenterDelegate
{

  // MARK: - Callback

  /// Wired by `AppDelegate` to `KeepAwakeManager.disable()`.
  public var onDisableRequested: () -> Void = {}

  // MARK: - State

  /// `true` once `requestAuthorization` has been called (not granted — just called).
  private var authorizationRequested = false
  /// `true` when authorization was granted; `false` means silent no-op for warnings.
  private var authorizationGranted = false

  // MARK: - BatteryWarningNotifying

  /// Requests `[.alert, .sound]` authorization on first call; registers the
  /// "Disable" notification action category. Idempotent.
  public func requestAuthorizationIfNeeded() {
    guard !authorizationRequested else { return }
    authorizationRequested = true

    let center = UNUserNotificationCenter.current()
    center.delegate = self

    // Register category with a single "Disable" action.
    let disableAction = UNNotificationAction(
      identifier: NotificationID.disableAction,
      title: NSLocalizedString("Disable", comment: "Keep-Awake notification action"),
      options: [.authenticationRequired]
    )
    let category = UNNotificationCategory(
      identifier: NotificationID.category,
      actions: [disableAction],
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([category])

    center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
      Task { @MainActor in
        self?.authorizationGranted = granted
      }
    }
  }

  /// Posts the battery-warning banner. No-op when authorization was denied
  /// or when `requestAuthorizationIfNeeded()` was never called.
  public func postBatteryWarning() {
    guard authorizationGranted else { return }

    let content = UNMutableNotificationContent()
    content.title = NSLocalizedString(
      "Keep Awake is active on battery",
      comment: "Keep-Awake battery warning title"
    )
    content.body = NSLocalizedString(
      "Tap Disable to turn off Keep Awake and save battery.",
      comment: "Keep-Awake battery warning body"
    )
    content.categoryIdentifier = NotificationID.category
    content.sound = .default

    let request = UNNotificationRequest(
      identifier: NotificationID.requestID,
      content: content,
      trigger: nil  // deliver immediately
    )

    UNUserNotificationCenter.current().add(request)
  }

  /// Removes the battery-warning banner if it is still displayed.
  public func clearBatteryWarning() {
    UNUserNotificationCenter.current()
      .removeDeliveredNotifications(withIdentifiers: [NotificationID.requestID])
    UNUserNotificationCenter.current()
      .removePendingNotificationRequests(withIdentifiers: [NotificationID.requestID])
  }

  // MARK: - UNUserNotificationCenterDelegate

  /// Routes the "Disable" tap action back to `onDisableRequested`.
  ///
  /// `nonisolated` because `UNUserNotificationCenterDelegate` methods are
  /// called on an arbitrary background thread by the system, not on the main actor.
  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier == NotificationID.requestID,
      response.actionIdentifier == NotificationID.disableAction
    {
      Task { @MainActor in self.onDisableRequested() }
    }
    completionHandler()
  }

  /// Allows the banner to display even while the app is in the foreground.
  ///
  /// `nonisolated` because `UNUserNotificationCenterDelegate` methods are
  /// called on an arbitrary background thread by the system, not on the main actor.
  public nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }
}
