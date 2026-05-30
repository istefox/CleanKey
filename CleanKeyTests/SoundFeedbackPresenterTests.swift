import XCTest

@testable import CleanKey

@MainActor
final class SoundFeedbackPresenterTests: XCTestCase {

  private func makeSUT(
    real: FakeLockPresenter = FakeLockPresenter(),
    player: FakeSoundPlayer = FakeSoundPlayer()
  ) -> (sut: SoundFeedbackPresenter, real: FakeLockPresenter, player: FakeSoundPlayer) {
    let sut = SoundFeedbackPresenter(real: real, player: player)
    return (sut, real, player)
  }

  private func makeSettings(soundFeedback: Bool, suiteName: String = #function) -> LockSettings {
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    var s = LockSettings(defaults: defaults)
    s.soundFeedback = soundFeedback
    return s
  }

  // MARK: - Forwarding

  func testPresentAlwaysForwardsToReal() {
    let (sut, real, _) = makeSUT()
    sut.present()
    XCTAssertEqual(real.presentCallCount, 1)
  }

  func testDismissAlwaysForwardsToReal() {
    let (sut, real, _) = makeSUT()
    sut.dismiss()
    XCTAssertEqual(real.dismissCallCount, 1)
  }

  // MARK: - Sound enabled

  func testPresentPlaysLockSoundWhenEnabled() {
    let (sut, _, player) = makeSUT()
    sut.configure(settings: makeSettings(soundFeedback: true))
    sut.present()
    XCTAssertEqual(player.played, [.lock])
  }

  func testDismissPlaysUnlockSoundWhenEnabled() {
    let (sut, _, player) = makeSUT()
    sut.configure(settings: makeSettings(soundFeedback: true))
    sut.dismiss()
    XCTAssertEqual(player.played, [.unlock])
  }

  // MARK: - Sound disabled

  func testPresentPlaysNoSoundWhenDisabled() {
    let (sut, _, player) = makeSUT()
    sut.configure(settings: makeSettings(soundFeedback: false))
    sut.present()
    XCTAssertTrue(player.played.isEmpty)
  }

  func testDismissPlaysNoSoundWhenDisabled() {
    let (sut, _, player) = makeSUT()
    sut.configure(settings: makeSettings(soundFeedback: false))
    sut.dismiss()
    XCTAssertTrue(player.played.isEmpty)
  }

  // MARK: - Default (no configure called)

  func testDefaultEnabledStateIsTrue() {
    let (sut, _, player) = makeSUT()
    // No configure() call — should default to enabled (sound on by default).
    sut.present()
    XCTAssertEqual(player.played, [.lock])
  }

  // MARK: - Configure re-reads setting each lock

  func testConfigureCanToggleFromEnabledToDisabled() {
    let (sut, _, player) = makeSUT()
    sut.configure(settings: makeSettings(soundFeedback: true))
    sut.present()
    sut.configure(settings: makeSettings(soundFeedback: false, suiteName: #function + "2"))
    sut.present()
    XCTAssertEqual(player.played, [.lock])
  }
}
