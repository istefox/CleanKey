import SwiftUI

struct GeneralSettingsView: View {

  @Bindable var viewModel: SettingsViewModel

  var body: some View {
    Form {
      Section("Lock Duration") {
        VStack(alignment: .leading, spacing: 8) {
          Text(durationLabel)
            .monospacedDigit()
            .frame(minWidth: 80, alignment: .leading)
          Slider(value: $viewModel.sliderPosition, in: 0...1, step: 1.0 / 20.0)
        }
      }

      Section("Trackpad") {
        Picker("Trackpad during lock", selection: $viewModel.trackpadMode) {
          Text("Locked").tag(TrackpadMode.locked)
          Text("Free").tag(TrackpadMode.free)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      Section("Emergency unlock") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Triple-Escape speed: \(escapeIntervalLabel)")
            .monospacedDigit()
            .frame(minWidth: 80, alignment: .leading)
          Slider(
            value: $viewModel.escapeInterval,
            in: LockSettings.escapeIntervalMinimum...LockSettings.escapeIntervalMaximum,
            step: 0.5
          )
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var escapeIntervalLabel: String {
    let value = viewModel.escapeInterval
    return String(format: "%.1f s", value)
  }

  private var durationLabel: String {
    let duration = TwoZoneSlider.durationForPosition(viewModel.sliderPosition)
    let total = Int(duration)
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
}
