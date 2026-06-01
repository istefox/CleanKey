import SwiftUI

struct KeepAwakeSettingsView: View {

  @Bindable var viewModel: SettingsViewModel

  var body: some View {
    Form {
      Section("Sleep Prevention") {
        Picker("Mode", selection: $viewModel.keepAwakeMode) {
          Text("Screen + System").tag(KeepAwakeMode.full)
          Text("System only").tag(KeepAwakeMode.systemOnly)
        }
        .pickerStyle(.segmented)
        Text(
          viewModel.keepAwakeMode == .full
            ? "Keeps both the display and the Mac awake."
            : "Keeps the Mac awake but lets the display sleep normally."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Duration Cap") {
        Picker("Maximum duration", selection: $viewModel.keepAwakeDurationCap) {
          ForEach(KeepAwakeSettings.allowedCaps, id: \.self) { cap in
            Text(capLabel(for: cap)).tag(cap)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        Text(
          "Keep awake will auto-disable after the selected duration. Choose \"No limit\" to keep it active indefinitely."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("On Launch") {
        Toggle(
          "Re-enable keep awake when CleanKey starts",
          isOn: $viewModel.keepAwakeRestoreOnLaunch
        )
      }
    }
    .formStyle(.grouped)
  }

  // All values in KeepAwakeSettings.allowedCaps are whole-hour multiples of 3600.
  private func capLabel(for seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "No limit" }
    let hours = Int(seconds) / 3600
    return hours == 1 ? "1 hour" : "\(hours) hours"
  }
}
