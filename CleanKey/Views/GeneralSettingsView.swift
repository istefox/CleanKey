import SwiftUI

struct GeneralSettingsView: View {

  @Bindable var viewModel: SettingsViewModel
  @State var settings: LockSettings

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

      Section("Lock Scope") {
        Picker("Lock scope", selection: $viewModel.lockScope) {
          Text("Both").tag(LockScope.all)
          Text("Keyboard").tag(LockScope.keyboardOnly)
          Text("Trackpad").tag(LockScope.trackpadOnly)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      Section("Startup") {
        Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
      }

      Section("Sound") {
        Toggle("Sound feedback on lock and unlock", isOn: $viewModel.soundFeedback)
      }

      Section("Global Hotkey") {
        HStack {
          HotkeyRecorderView(settings: $settings)
            .frame(minWidth: 140, minHeight: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
          Button("Clear") {
            settings.hotkeyBinding = nil
            NotificationCenter.default.post(name: .cleanKeyHotkeyChanged, object: nil)
          }
          .disabled(settings.hotkeyBinding == nil)
        }
        Text("When locked: extends the current lock duration")
          .font(.caption)
          .foregroundStyle(.secondary)
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
