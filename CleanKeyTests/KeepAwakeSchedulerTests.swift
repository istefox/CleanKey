import XCTest

@testable import CleanKey

@MainActor
final class KeepAwakeSchedulerTests: XCTestCase {

  private let t0 = Date(timeIntervalSince1970: 1_000_000)

  private func makeScheduler(
    clock: ClockBox,
    onStart: @escaping () -> Void = {},
    onEnd: @escaping () -> Void = {}
  ) -> KeepAwakeScheduler {
    KeepAwakeScheduler(clock: { clock.now }, onStart: onStart, onEnd: onEnd)
  }

  // MARK: - arm / clear

  func testArmStoresSchedule() {
    let clock = ClockBox(t0)
    let sut = makeScheduler(clock: clock)
    let schedule = KeepAwakeSchedule(startDate: t0.addingTimeInterval(10), endDate: t0.addingTimeInterval(100))
    sut.arm(schedule)
    XCTAssertNotNil(sut.armedSchedule)
    XCTAssertEqual(sut.armedSchedule, schedule)
  }

  func testClearDropsSchedule() {
    let clock = ClockBox(t0)
    let sut = makeScheduler(clock: clock)
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    sut.clear()
    XCTAssertNil(sut.armedSchedule)
  }

  // MARK: - immediate start (startDate == nil)

  func testArmWithNilStartFiresOnStartImmediately() {
    let clock = ClockBox(t0)
    var started = 0
    let sut = makeScheduler(clock: clock, onStart: { started += 1 })
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    XCTAssertEqual(started, 1)
  }

  func testTickAfterImmediateStartDoesNotDoubleFireOnStart() {
    let clock = ClockBox(t0)
    var started = 0
    let sut = makeScheduler(clock: clock, onStart: { started += 1 })
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    sut.tick()   // already started — should be no-op
    XCTAssertEqual(started, 1)
  }

  // MARK: - deferred start

  func testTickBeforeStartDoesNotFireOnStart() {
    let clock = ClockBox(t0)
    var started = 0
    let sut = makeScheduler(clock: clock, onStart: { started += 1 })
    sut.arm(KeepAwakeSchedule(startDate: t0.addingTimeInterval(30), endDate: t0.addingTimeInterval(60)))
    sut.tick()  // still before start
    XCTAssertEqual(started, 0)
  }

  func testTickAtStartFiresOnStart() {
    let clock = ClockBox(t0)
    var started = 0
    let sut = makeScheduler(clock: clock, onStart: { started += 1 })
    sut.arm(KeepAwakeSchedule(startDate: t0.addingTimeInterval(30), endDate: t0.addingTimeInterval(60)))
    clock.now = t0.addingTimeInterval(30)
    sut.tick()
    XCTAssertEqual(started, 1)
  }

  func testTickAfterStartDoesNotDoubleFireOnStart() {
    let clock = ClockBox(t0)
    var started = 0
    let sut = makeScheduler(clock: clock, onStart: { started += 1 })
    sut.arm(KeepAwakeSchedule(startDate: t0.addingTimeInterval(30), endDate: t0.addingTimeInterval(60)))
    clock.now = t0.addingTimeInterval(30)
    sut.tick()
    clock.now = t0.addingTimeInterval(35)
    sut.tick()
    XCTAssertEqual(started, 1)
  }

  // MARK: - end

  func testTickAtEndFiresOnEndAndClears() {
    let clock = ClockBox(t0)
    var ended = 0
    let sut = makeScheduler(clock: clock, onEnd: { ended += 1 })
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    clock.now = t0.addingTimeInterval(60)
    sut.tick()
    XCTAssertEqual(ended, 1)
    XCTAssertNil(sut.armedSchedule)
  }

  func testTickAfterClearDoesNotFireCallbacks() {
    let clock = ClockBox(t0)
    var ended = 0
    let sut = makeScheduler(clock: clock, onEnd: { ended += 1 })
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    sut.clear()
    clock.now = t0.addingTimeInterval(120)
    sut.tick()   // cleared — must be a no-op
    XCTAssertEqual(ended, 0)
  }

  // MARK: - re-arm replaces existing schedule

  func testRearmReplacesSchedule() {
    let clock = ClockBox(t0)
    var startCount = 0
    let sut = makeScheduler(clock: clock, onStart: { startCount += 1 })
    sut.arm(KeepAwakeSchedule(startDate: nil, endDate: t0.addingTimeInterval(60)))
    XCTAssertEqual(startCount, 1)

    // Arm again with a deferred start — onStart should NOT fire again immediately.
    sut.arm(KeepAwakeSchedule(startDate: t0.addingTimeInterval(30), endDate: t0.addingTimeInterval(120)))
    XCTAssertEqual(startCount, 1)
    XCTAssertNotNil(sut.armedSchedule)
  }
}
