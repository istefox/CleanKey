import XCTest

@testable import CleanKey

@MainActor
final class TimerPickerViewModelTests: XCTestCase {

  private func makeSettings() -> LockSettings {
    LockSettings(defaults: UserDefaults(suiteName: "TimerPickerViewModelTests-\(UUID())")!)
  }

  func testInitialDurationMatchesSettings() {
    var settings = makeSettings()
    settings.lastDuration = 180
    let vm = TimerPickerViewModel(settings: settings)
    XCTAssertEqual(vm.selectedDuration, 180, accuracy: 0.001)
  }

  func testFormattedDurationForUnderOneMinute() {
    var settings = makeSettings()
    settings.lastDuration = 45
    let vm = TimerPickerViewModel(settings: settings)
    XCTAssertEqual(vm.formattedDuration, "45 s")
  }

  func testFormattedDurationForExactMinutes() {
    var settings = makeSettings()
    settings.lastDuration = 120
    let vm = TimerPickerViewModel(settings: settings)
    XCTAssertEqual(vm.formattedDuration, "2 min")
  }

  func testFormattedDurationForMinutesAndSeconds() {
    var settings = makeSettings()
    settings.lastDuration = 150
    let vm = TimerPickerViewModel(settings: settings)
    XCTAssertEqual(vm.formattedDuration, "2 min 30 s")
  }

  func testPersistSavesSelectedDurationToSettings() {
    var settings = makeSettings()
    settings.lastDuration = 60
    let vm = TimerPickerViewModel(settings: settings)
    vm.selectedDuration = 300
    vm.persist()
    XCTAssertEqual(settings.lastDuration, 300, accuracy: 0.001)
  }
}
