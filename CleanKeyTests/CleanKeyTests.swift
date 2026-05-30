import XCTest

@testable import CleanKey

final class CleanKeyTests: XCTestCase {
  func testLockSettingsDefaultDuration() {
    let defaults = UserDefaults(suiteName: "it.stefer.CleanKey.tests.smoke")!
    defaults.removePersistentDomain(forName: "CleanKeyTests-smoke")
    let settings = LockSettings(defaults: defaults)
    XCTAssertEqual(settings.lastDuration, LockSettings.defaultDuration)
  }
}
