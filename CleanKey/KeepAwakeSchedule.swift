import Foundation

/// A resolved schedule: nil startDate means "begin immediately".
public struct KeepAwakeSchedule: Equatable, Sendable {
  public let startDate: Date?
  public let endDate: Date

  public init(startDate: Date?, endDate: Date) {
    self.startDate = startDate
    self.endDate = endDate
  }
}

/// How the user configured the schedule.
public enum KeepAwakeScheduleMode: String, CaseIterable, Sendable {
  case startAndEnd
  case endOnly
  case startAndDuration
}

/// Pure date-math builder — no side effects, fully injectable clock + calendar.
public enum KeepAwakeScheduleBuilder {

  /// Resolves draft picker values into an absolute KeepAwakeSchedule.
  /// Returns nil for incoherent input (non-positive span, etc.).
  ///
  /// - Parameters:
  ///   - mode: Which UI mode is active.
  ///   - startTime: A Date whose hour+minute components are used as the start clock time.
  ///   - endTime: A Date whose hour+minute components are used as the end clock time.
  ///   - durationHours: Hours for the startAndDuration mode; clamped to 1…24.
  ///   - now: Reference instant (inject for deterministic tests; pass Date() in production).
  ///   - calendar: Calendar for date math (inject for deterministic tests).
  public static func resolve(
    mode: KeepAwakeScheduleMode,
    startTime: Date,
    endTime: Date,
    durationHours: Double,
    now: Date,
    calendar: Calendar = .current
  ) -> KeepAwakeSchedule? {
    switch mode {
    case .startAndEnd:
      let start = nextOccurrence(of: startTime, after: now, calendar: calendar)
      let end = nextOccurrence(of: endTime, after: start, calendar: calendar)
      guard end > start else { return nil }
      return KeepAwakeSchedule(startDate: start, endDate: end)

    case .endOnly:
      let end = nextOccurrence(of: endTime, after: now, calendar: calendar)
      guard end > now else { return nil }
      return KeepAwakeSchedule(startDate: nil, endDate: end)

    case .startAndDuration:
      let clampedHours = max(1, min(24, durationHours))
      let start = nextOccurrence(of: startTime, after: now, calendar: calendar)
      let end = start.addingTimeInterval(clampedHours * 3600)
      guard end > start else { return nil }
      return KeepAwakeSchedule(startDate: start, endDate: end)
    }
  }

  // MARK: - Private helpers

  /// Returns the next occurrence of `time`'s hour+minute components that is
  /// strictly after `reference`. If same-day h:m is still in the future, returns
  /// it today; otherwise adds one day.
  private static func nextOccurrence(
    of time: Date,
    after reference: Date,
    calendar: Calendar
  ) -> Date {
    let components = calendar.dateComponents([.hour, .minute], from: time)
    var refComponents = calendar.dateComponents([.year, .month, .day], from: reference)
    refComponents.hour = components.hour
    refComponents.minute = components.minute
    refComponents.second = 0

    if let candidate = calendar.date(from: refComponents), candidate > reference {
      return candidate
    }
    // Roll to next day.
    refComponents.day = (refComponents.day ?? 0) + 1
    return calendar.date(from: refComponents) ?? reference.addingTimeInterval(86400)
  }
}
