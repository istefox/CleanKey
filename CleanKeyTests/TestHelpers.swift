import XCTest

@testable import CleanKey

// MARK: - Clock box

// @unchecked Sendable is safe: ClockBox is only ever mutated from @MainActor test methods.
final class ClockBox: @unchecked Sendable {
  var now: Date
  init(_ date: Date = Date(timeIntervalSince1970: 0)) { now = date }
}

// MARK: - Shared fakes

@MainActor
final class FakeLockPresenter: LockPresenting {
  var presentCallCount = 0
  var dismissCallCount = 0

  func present() { presentCallCount += 1 }
  func dismiss() { dismissCallCount += 1 }
}

@MainActor
final class FakeEventTapController: EventTapControlling {
  var installCallCount = 0
  var removeCallCount = 0
  var isEnabled: Bool = true

  func install() { installCallCount += 1 }
  func remove() { removeCallCount += 1 }
}

// @unchecked Sendable is safe: only ever mutated from @MainActor contexts (LockManager is @MainActor).
final class FakeNotifier: Notifying, @unchecked Sendable {
  var messages: [String] = []
  func post(message: String) { messages.append(message) }
}

// @unchecked Sendable is safe: only ever mutated from @MainActor test methods.
final class FakeTrustChecker: TrustChecking, @unchecked Sendable {
  var trusted: Bool = true
  var isTrusted: Bool { trusted }
}

// MARK: - LockState test-only Equatable
// WARNING: ignores escapeCombo — .locked states with different combo progress compare equal.
// Use pattern matching (guard case .locked = state) when combo content matters.
extension LockState: Equatable {
  public static func == (lhs: LockState, rhs: LockState) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle): return true
    case (.locked(let la, _), .locked(let ra, _)): return la == ra
    default: return false
    }
  }
}
