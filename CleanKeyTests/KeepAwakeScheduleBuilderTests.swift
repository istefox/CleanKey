import XCTest

@testable import CleanKey

final class KeepAwakeScheduleBuilderTests: XCTestCase {

  // Fixed reference: 2025-06-22 10:00:00 UTC
  private let now = Date(timeIntervalSince1970: 1_750_586_400)
  private var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }()

  // Helper: build a Date with specific h:m in UTC on 2025-06-22.
  private func time(hour: Int, minute: Int) -> Date {
    var comps = DateComponents()
    comps.year = 2025; comps.month = 6; comps.day = 22
    comps.hour = hour; comps.minute = minute; comps.second = 0
    return cal.date(from: comps)!
  }

  // MARK: - endOnly

  func testEndOnlyFutureEndReturnsNilStart() throws {
    let end = time(hour: 11, minute: 0)   // 11:00 > 10:00 (now)
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .endOnly,
        startTime: time(hour: 9, minute: 0),
        endTime: end,
        durationHours: 1,
        now: now,
        calendar: cal
      )
    )
    XCTAssertNil(result.startDate)
    XCTAssertEqual(result.endDate, end)
  }

  func testEndOnlyPastEndRollsToNextDay() throws {
    // 09:00 is before now (10:00); must roll to tomorrow.
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .endOnly,
        startTime: time(hour: 9, minute: 0),
        endTime: time(hour: 9, minute: 0),
        durationHours: 1,
        now: now,
        calendar: cal
      )
    )
    XCTAssertNil(result.startDate)
    let expected = cal.date(byAdding: .day, value: 1, to: time(hour: 9, minute: 0))!
    XCTAssertEqual(result.endDate, expected)
  }

  // MARK: - startAndEnd

  func testStartAndEndBothFuture() throws {
    let start = time(hour: 11, minute: 0)
    let end = time(hour: 13, minute: 0)
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndEnd,
        startTime: start,
        endTime: end,
        durationHours: 1,
        now: now,
        calendar: cal
      )
    )
    XCTAssertEqual(result.startDate, start)
    XCTAssertEqual(result.endDate, end)
  }

  func testStartAndEndEndBeforeStartRollsEndByOneDay() throws {
    // start=11:00 (today, future); end=10:00 which is before start → must roll end to next day.
    let start = time(hour: 11, minute: 0)
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndEnd,
        startTime: start,
        endTime: time(hour: 10, minute: 0),
        durationHours: 1,
        now: now,
        calendar: cal
      )
    )
    let expectedEnd = cal.date(byAdding: .day, value: 1, to: time(hour: 10, minute: 0))!
    XCTAssertEqual(result.startDate, start)
    XCTAssertEqual(result.endDate, expectedEnd)
  }

  func testStartAndEndPastStartRollsStartToNextDay() throws {
    // now = 10:00; start = 09:00 → rolls to tomorrow 09:00.
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndEnd,
        startTime: time(hour: 9, minute: 0),
        endTime: time(hour: 11, minute: 0),
        durationHours: 1,
        now: now,
        calendar: cal
      )
    )
    let expectedStart = cal.date(byAdding: .day, value: 1, to: time(hour: 9, minute: 0))!
    XCTAssertEqual(result.startDate, expectedStart)
    // end must be > start (which is tomorrow 09:00); 11:00 same day as start → also rolls.
    XCTAssertGreaterThan(result.endDate, result.startDate!)
  }

  // MARK: - startAndDuration

  func testStartAndDurationFutureStart() throws {
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndDuration,
        startTime: time(hour: 11, minute: 0),
        endTime: time(hour: 9, minute: 0),   // ignored in this mode
        durationHours: 2,
        now: now,
        calendar: cal
      )
    )
    let expectedStart = time(hour: 11, minute: 0)
    let expectedEnd = expectedStart.addingTimeInterval(2 * 3600)
    XCTAssertEqual(result.startDate, expectedStart)
    XCTAssertEqual(result.endDate.timeIntervalSince1970, expectedEnd.timeIntervalSince1970, accuracy: 1.0)
  }

  func testStartAndDurationClampsHoursBelow1() throws {
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndDuration,
        startTime: time(hour: 11, minute: 0),
        endTime: time(hour: 9, minute: 0),
        durationHours: 0,          // below min → clamped to 1
        now: now,
        calendar: cal
      )
    )
    let start = result.startDate!
    XCTAssertEqual(result.endDate.timeIntervalSince(start), 3600.0, accuracy: 1.0)
  }

  func testStartAndDurationClampsHoursAbove24() throws {
    let result = try XCTUnwrap(
      KeepAwakeScheduleBuilder.resolve(
        mode: .startAndDuration,
        startTime: time(hour: 11, minute: 0),
        endTime: time(hour: 9, minute: 0),
        durationHours: 100,        // above max → clamped to 24
        now: now,
        calendar: cal
      )
    )
    let start = result.startDate!
    XCTAssertEqual(result.endDate.timeIntervalSince(start), 24.0 * 3600, accuracy: 1)
  }
}
