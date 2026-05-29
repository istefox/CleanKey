import SwiftUI

@Observable
@MainActor
final class TimerPickerViewModel {
  var selectedDuration: TimeInterval

  var formattedDuration: String {
    let total = Int(selectedDuration)
    let minutes = total / 60
    let seconds = total % 60
    if minutes == 0 {
      return "\(seconds) s"
    } else if seconds == 0 {
      return "\(minutes) min"
    } else {
      return "\(minutes) min \(seconds) s"
    }
  }

  private var settings: LockSettings

  init(settings: LockSettings) {
    self.settings = settings
    selectedDuration = settings.lastDuration
  }

  func persist() {
    settings.lastDuration = selectedDuration
  }
}

struct TimerPickerView: View {
  @State private var viewModel: TimerPickerViewModel
  let onStart: (TimeInterval) -> Void

  init(settings: LockSettings, onStart: @escaping (TimeInterval) -> Void) {
    _viewModel = State(initialValue: TimerPickerViewModel(settings: settings))
    self.onStart = onStart
  }

  var body: some View {
    VStack(spacing: 16) {
      Text("Lock duration")
        .font(.headline)

      Slider(
        value: $viewModel.selectedDuration,
        in: LockSettings.minimumDuration...LockSettings.maximumDuration,
        step: 5
      )

      Text(viewModel.formattedDuration)
        .monospacedDigit()
        .frame(minWidth: 80)

      Button("Start") {
        viewModel.persist()
        onStart(viewModel.selectedDuration)
      }
      .keyboardShortcut(.defaultAction)
    }
    .padding()
    .frame(width: 240)
  }
}
