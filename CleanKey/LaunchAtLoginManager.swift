import ServiceManagement
import os

protocol LaunchAtLoginControlling {
  func apply(_ enabled: Bool)
}

struct LaunchAtLoginManager: LaunchAtLoginControlling {

  private let logger = Logger(subsystem: "it.stefer.CleanKey", category: "LaunchAtLogin")

  func apply(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      logger.error(
        "SMAppService \(enabled ? "register" : "unregister") failed: \(error.localizedDescription)"
      )
    }
  }
}
