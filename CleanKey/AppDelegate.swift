import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

  private var menuBarController: MenuBarController?
  private var settingsWindowController: SettingsWindowController?

  // Keep-awake stack — held strongly so ARC doesn't reclaim before teardown.
  private var keepAwakeSettings = KeepAwakeSettings()
  private var keepAwakeManager: KeepAwakeManager?
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
      persist: { [weak self] value in self?.keepAwakeSettings.lastActiveState = value }
    )
    keepAwakeManager = manager

    // 3. Wire the notifier's disable callback.
    notifier.onDisableRequested = { [weak manager] in
      manager?.disable()
    }

    // 4. Build MenuBarController with the real KeepAwakeManager.
    menuBarController = MenuBarController(
      settings: settings,
      settingsWindowController: swc,
      keepAwakeManager: manager
    )

    // 5. Restore-on-launch (SPEC §4.5, §7).
    //    Cap timer restarts fresh from launch — elapsed cap time is not persisted
    //    across launches (accepted v1.1 behaviour, documented in ADR-003 Consequences).
    if keepAwakeSettings.restoreOnLaunch && keepAwakeSettings.lastActiveState {
      manager.enable()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    // Release IOPMAssertions cleanly on quit (SPEC §7).
    // The kernel also reaps assertions on process death, but explicit release
    // ensures clean state for pmset diagnostics.
    keepAwakeManager?.disable()
  }
}
