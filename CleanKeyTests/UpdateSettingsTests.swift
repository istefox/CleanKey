import XCTest

@testable import CleanKey

final class UpdateSettingsTests: XCTestCase {

  private var defaults: UserDefaults!
  private var sut: UpdateSettings!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: "com.cleankey.test.updatesettings.\(name)")!
    defaults.removePersistentDomain(forName: "com.cleankey.test.updatesettings.\(name)")
    sut = UpdateSettings(defaults: defaults)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: "com.cleankey.test.updatesettings.\(name)")
    sut = nil
    defaults = nil
    super.tearDown()
  }

  func testDefaultFrequencyIsDaily() {
    XCTAssertEqual(sut.frequency, .daily)
  }

  func testDefaultLastCheckDateIsNil() {
    XCTAssertNil(sut.lastCheckDate)
  }

  func testFrequencyRoundTrip() {
    sut.frequency = .weekly
    let reloaded = UpdateSettings(defaults: defaults)
    XCTAssertEqual(reloaded.frequency, .weekly)
  }

  func testLastCheckDateRoundTrip() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    sut.lastCheckDate = date
    let reloaded = UpdateSettings(defaults: defaults)
    let reloadedInterval = try XCTUnwrap(reloaded.lastCheckDate).timeIntervalSince1970
    XCTAssertEqual(reloadedInterval, date.timeIntervalSince1970, accuracy: 0.001)
  }

  func testSettingLastCheckDateToNilRemovesKey() {
    sut.lastCheckDate = Date()
    XCTAssertNotNil(sut.lastCheckDate)
    sut.lastCheckDate = nil
    XCTAssertNil(sut.lastCheckDate)
    let reloaded = UpdateSettings(defaults: defaults)
    XCTAssertNil(reloaded.lastCheckDate)
  }

  func testAllFrequenciesRoundTrip() {
    for freq in UpdateCheckFrequency.allCases {
      sut.frequency = freq
      let reloaded = UpdateSettings(defaults: defaults)
      XCTAssertEqual(reloaded.frequency, freq, "Round-trip failed for \(freq)")
    }
  }
}
