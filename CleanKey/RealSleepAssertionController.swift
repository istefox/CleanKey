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

  /// `true` when the system-sleep assertion is held (always created in both modes).
  public var isHeld: Bool { systemID != nil }

  /// Creates sleep assertions according to `mode`.
  /// `.full`: creates `PreventUserIdleDisplaySleep` then `PreventUserIdleSystemSleep`.
  /// `.systemOnly`: creates `PreventUserIdleSystemSleep` only; display can sleep normally.
  /// On any failure, any already-created assertion is released before returning `false`.
  public func createAssertions(reason: String, mode: KeepAwakeMode) -> Bool {
    if mode == .full {
      var dID = IOPMAssertionID(0)
      let displayResult = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason as CFString,
        &dID
      )
      guard displayResult == kIOReturnSuccess else { return false }
      displayID = dID
    }

    var sID = IOPMAssertionID(0)
    let systemResult = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason as CFString,
      &sID
    )

    guard systemResult == kIOReturnSuccess else {
      if let dID = displayID { IOPMAssertionRelease(dID) }
      displayID = nil
      return false
    }

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
