import SwiftUI

@Observable
final class CountdownModel {
  var remainingTime: TimeInterval

  init(remainingTime: TimeInterval = 0) {
    self.remainingTime = remainingTime
  }
}

struct CountdownView: View {
  var model: CountdownModel

  private var formattedTime: String {
    let total = max(0, Int(model.remainingTime))
    let minutes = total / 60
    let seconds = total % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  var body: some View {
    VStack(spacing: 12) {
      Text(formattedTime)
        .font(.system(size: 48, weight: .light, design: .monospaced))
        .foregroundStyle(.white)

      Text("Triple-press Esc to unlock")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.7))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }
}
