import Foundation
import IOKit.pwr_mgt

/// Production implementation of `SleepAssertionControlling`.
///
/// Holds two `IOPMAssertionID` values — one preventing display sleep, one
/// preventing idle system sleep — and is the **single owner** of both.
/// IDs never escape the class; `releaseAssertions()` nils them atomically.
///
/// On any `IOPMAssertionCreateWithName` failure the successfully created
/// assertion (if any) is released before returning `false`, so a half-created
/// pair is never left dangling (SPEC §7).
@MainActor
public final class RealSleepAssertionController: SleepAssertionControlling {

  // MARK: - State

  private var displayID: IOPMAssertionID?
  private var systemID: IOPMAssertionID?

  // MARK: - SleepAssertionControlling

  public var isHeld: Bool { displayID != nil && systemID != nil }

  /// Creates `PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep`
  /// assertions with the given reason string. Returns `false` on any failure,
  /// releasing whichever assertion succeeded first.
  public func createAssertions(reason: String) -> Bool {
    var dID = IOPMAssertionID(0)
    let displayResult = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason as CFString,
      &dID
    )

    guard displayResult == kIOReturnSuccess else {
      return false
    }

    var sID = IOPMAssertionID(0)
    let systemResult = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason as CFString,
      &sID
    )

    guard systemResult == kIOReturnSuccess else {
      IOPMAssertionRelease(dID)
      return false
    }

    displayID = dID
    systemID = sID
    return true
  }

  /// Releases both held assertions. Idempotent — safe to call when not held.
  public func releaseAssertions() {
    if let id = displayID {
      IOPMAssertionRelease(id)
      displayID = nil
    }
    if let id = systemID {
      IOPMAssertionRelease(id)
      systemID = nil
    }
  }
}
