import AppKit
import Foundation
import Observation
import UserNotifications

// MARK: - UpdateNotifying

@MainActor
public protocol UpdateNotifying: AnyObject {
  func requestAuthorizationIfNeeded()
  func notifyUpdateAvailable(_ release: ReleaseInfo)
}

// MARK: - Real notifier

@MainActor
final class UpdateNotifier: UpdateNotifying {
  func requestAuthorizationIfNeeded() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func notifyUpdateAvailable(_ release: ReleaseInfo) {
    let content = UNMutableNotificationContent()
    content.title = "CleanKey update available"
    content.body = "Version \(release.version) is ready to download."
    let request = UNNotificationRequest(
      identifier: "com.cleankey.update-available",
      content: content,
      trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
  }
}

// MARK: - UpdateStatus

enum UpdateStatus {
  case idle
  case checking
  case upToDate(Date)
  case available(ReleaseInfo)
  case downloading
  case installing
  case failed(String)
}

// MARK: - UpdateManager

/// Coordinates update checks, download, and mount.
/// Parallel peer of `KeepAwakeManager` — `AppDelegate` owns it.
@MainActor
@Observable
final class UpdateManager {

  // MARK: - Injected seams

  private let checker: UpdateChecker
  private let persistLastCheck: (Date?) -> Void
  private let download: (URL) async throws -> URL
  private let openFile: (URL) -> Void
  private let notifier: any UpdateNotifying
  private let clock: () -> Date

  // MARK: - State

  var status: UpdateStatus = .idle
  private var checkTimer: Timer?

  // MARK: - Init

  init(
    checker: UpdateChecker,
    persistLastCheck: @escaping (Date?) -> Void = { _ in },
    clock: @escaping () -> Date = Date.init,
    download: @escaping (URL) async throws -> URL = { url in
      let (tempURL, _) = try await URLSession.shared.download(from: url)
      let downloadsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads")
      let destURL = downloadsDir.appendingPathComponent(url.lastPathComponent)
      try? FileManager.default.removeItem(at: destURL)
      try FileManager.default.moveItem(at: tempURL, to: destURL)
      return destURL
    },
    openFile: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
    notifier: any UpdateNotifying
  ) {
    self.checker = checker
    self.persistLastCheck = persistLastCheck
    self.clock = clock
    self.download = download
    self.openFile = openFile
    self.notifier = notifier
  }

  // MARK: - Public API

  /// Runs an update check. `userTriggered` controls whether a found update fires a notification.
  func checkNow(userTriggered: Bool = true) async {
    switch status {
    case .checking, .downloading, .installing:
      return
    default:
      break
    }
    status = .checking
    do {
      if let release = try await checker.checkForUpdate() {
        let now = clock()
        persistLastCheck(now)
        status = .available(release)
        if !userTriggered {
          notifier.notifyUpdateAvailable(release)
        }
      } else {
        let now = clock()
        persistLastCheck(now)
        status = .upToDate(now)
      }
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  /// Downloads the release DMG to ~/Downloads and mounts it.
  func downloadAndMount(_ release: ReleaseInfo) async {
    guard let dmgURL = release.dmgURL else {
      status = .failed("No DMG asset found for this release.")
      return
    }
    status = .downloading
    do {
      let localURL = try await download(dmgURL)
      openFile(localURL)
      status = .installing
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  /// (Re)arms the background check timer.
  /// Teardown order: stop timer → reschedule (consistent with ADR-001/ADR-003 discipline).
  func rearm(frequency: UpdateCheckFrequency) {
    checkTimer?.invalidate()
    checkTimer = nil
    switch frequency {
    case .never, .onLaunch:
      break
    case .daily:
      scheduleTimer(interval: 86_400)
    case .weekly:
      scheduleTimer(interval: 604_800)
    }
  }

  /// Stops the background timer. Call from `applicationWillTerminate`.
  func stop() {
    checkTimer?.invalidate()
    checkTimer = nil
  }

  // MARK: - Private

  private func scheduleTimer(interval: TimeInterval) {
    checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated { self.startBackgroundCheck() }
    }
  }

  private func startBackgroundCheck() {
    Task { await checkNow(userTriggered: false) }
  }
}
