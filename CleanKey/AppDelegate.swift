import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

  private var menuBarController: MenuBarController?
  private var settingsWindowController: SettingsWindowController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let settings = LockSettings()
    LaunchAtLoginManager().apply(settings.launchAtLogin)
    let swc = SettingsWindowController(settings: settings)
    settingsWindowController = swc
    menuBarController = MenuBarController(
      settings: settings,
      settingsWindowController: swc
    )
  }
}
