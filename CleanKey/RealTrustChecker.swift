import ApplicationServices

/// Concrete TrustChecking backed by AXIsProcessTrusted().
public final class RealTrustChecker: TrustChecking {
  public init() {}
  public var isTrusted: Bool { AXIsProcessTrusted() }
}
