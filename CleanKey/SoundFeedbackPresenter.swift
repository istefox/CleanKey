import AppKit

public enum FeedbackSound: Equatable {
  case lock
  case unlock
}

protocol SoundPlaying {
  func play(_ sound: FeedbackSound)
}

struct NSSoundPlayer: SoundPlaying {
  func play(_ sound: FeedbackSound) {
    let name: NSSound.Name = sound == .lock ? "Tink" : "Pop"
    NSSound(named: name)?.play()
  }
}

/// Decorates a LockPresenting instance with audible lock/unlock feedback.
/// Reads `settings.soundFeedback` via configure(settings:) before each lock.
@MainActor
final class SoundFeedbackPresenter: LockPresenting {

  private let real: any LockPresenting
  private let player: SoundPlaying
  private var enabled = true

  init(real: any LockPresenting, player: SoundPlaying = NSSoundPlayer()) {
    self.real = real
    self.player = player
  }

  func configure(settings: LockSettings) {
    enabled = settings.soundFeedback
    real.configure(settings: settings)
  }

  func present() {
    real.present()
    if enabled { player.play(.lock) }
  }

  func dismiss() {
    real.dismiss()
    if enabled { player.play(.unlock) }
  }

  func tick(remainingTime: TimeInterval) {
    real.tick(remainingTime: remainingTime)
  }
}
