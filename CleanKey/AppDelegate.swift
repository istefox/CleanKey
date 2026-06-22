import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

  private var menuBarController: MenuBarController?
  private var settingsWindowController: SettingsWindowController?

  // Keep-awake stack — held strongly so ARC doesn't reclaim before teardown.
  private var keepAwakeSettings = KeepAwakeSettings()
  private var keepAwakeManager: KeepAwakeManager?
  private var keepAwakeScheduler: KeepAwakeScheduler?
  private var keepAwakeSleepController: RealSleepAssertionController?
  private var keepAwakePowerObserver: RealPowerSourceObserver?
  private var keepAwakeNotifier: KeepAwakeNotifier?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // --- Lock stack ---
    let settings = LockSettings()
    LaunchAtLoginManager().apply(settings.launchAtLogin)
    let swc = SettingsWindowController(settings: settings, keepAwakeSettings: keepAwakeSettings)
    settingsWindowController = swc

    // --- Keep-awake stack (ADR-003 D2, construction order per plan Task 7) ---

    // 1. Build the three controllers/notifier.
    let sleepController = RealSleepAssertionController()
    let powerObserver = RealPowerSourceObserver()
    let notifier = KeepAwakeNotifier()
    keepAwakeSleepController = sleepController
    keepAwakePowerObserver = powerObserver
    keepAwakeNotifier = notifier

    // 2. Build KeepAwakeManager with cap and persist closures.
    //    Capture `self` (a class reference) — safe for @Sendable per Swift 6.
    let manager = KeepAwakeManager(
      assertions: sleepController,
      powerObserver: powerObserver,
      notifier: notifier,
      capProvider: { [weak self] in self?.keepAwakeSettings.durationCap ?? 0 },
      modeProvider: { [weak self] in self?.keepAwakeSettings.mode ?? .full },
      persist: { [weak self] value in self?.keepAwakeSettings.lastActiveState = value }
    )
    keepAwakeManager = manager

    // 3. Wire the notifier's disable callback.
    notifier.onDisableRequested = { [weak manager] in
      manager?.disable()
    }

    // 4. Build KeepAwakeScheduler as a parallel peer of KeepAwakeManager.
    let scheduler = KeepAwakeScheduler(
      onStart: { [weak manager] in manager?.enable() },
      onEnd: { [weak manager] in manager?.disable() }
    )
    keepAwakeScheduler = scheduler

    // 5. Build MenuBarController with the real KeepAwakeManager.
    menuBarController = MenuBarController(
      settings: settings,
      settingsWindowController: swc,
      keepAwakeManager: manager
    )

    // 6. Wire the schedule-changed callback from Settings.
    swc.onScheduleChanged = { [weak self] in self?.rearmScheduleFromSettings() }

    // 7. Restore-on-launch (SPEC §4.5, §7).
    //    Cap timer restarts fresh from launch — elapsed cap time is not persisted
    //    across launches (accepted v1.1 behaviour, documented in ADR-003 Consequences).
    if keepAwakeSettings.restoreOnLaunch && keepAwakeSettings.lastActiveState {
      manager.enable()
    }

    // 8. Rearm any persisted schedule from a prior session.
    rearmScheduleFromSettings()
  }

  private func rearmScheduleFromSettings() {
    guard let scheduler = keepAwakeScheduler else { return }
    guard let endDate = keepAwakeSettings.scheduleEndDate, endDate > Date() else {
      keepAwakeSettings.clearSchedule()
      scheduler.clear()
      return
    }
    let schedule = KeepAwakeSchedule(
      startDate: keepAwakeSettings.scheduleStartDate,
      endDate: endDate
    )
    scheduler.arm(schedule)
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Release IOPMAssertions cleanly on quit (SPEC §7).
    // The kernel also reaps assertions on process death, but explicit release
    // ensures clean state for pmset diagnostics.
    keepAwakeScheduler?.clear()
    keepAwakeManager?.disable()
  }
}
