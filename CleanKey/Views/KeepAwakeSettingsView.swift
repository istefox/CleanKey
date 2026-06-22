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

      Section("Schedule") {
        Picker("Mode", selection: $viewModel.keepAwakeScheduleMode) {
          Text("Start + End").tag(KeepAwakeScheduleMode.startAndEnd)
          Text("End only").tag(KeepAwakeScheduleMode.endOnly)
          Text("Start + Duration").tag(KeepAwakeScheduleMode.startAndDuration)
        }
        .pickerStyle(.menu)

        switch viewModel.keepAwakeScheduleMode {
        case .startAndEnd:
          DatePicker("Start", selection: $viewModel.keepAwakeScheduleStartTime,
                     displayedComponents: .hourAndMinute)
          DatePicker("End", selection: $viewModel.keepAwakeScheduleEndTime,
                     displayedComponents: .hourAndMinute)

        case .endOnly:
          DatePicker("End", selection: $viewModel.keepAwakeScheduleEndTime,
                     displayedComponents: .hourAndMinute)

        case .startAndDuration:
          DatePicker("Start", selection: $viewModel.keepAwakeScheduleStartTime,
                     displayedComponents: .hourAndMinute)
          HStack {
            Slider(
              value: $viewModel.keepAwakeScheduleDurationHours,
              in: 1...24,
              step: 1
            )
            Text("\(Int(viewModel.keepAwakeScheduleDurationHours)) h")
              .monospacedDigit()
              .frame(minWidth: 36, alignment: .trailing)
          }
        }

        Toggle("Arm schedule", isOn: $viewModel.keepAwakeScheduleArmed)

        if viewModel.keepAwakeScheduleArmed {
          Text(scheduleStatusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("No schedule set.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Helpers

  // All values in KeepAwakeSettings.allowedCaps are whole-hour multiples of 3600.
  private func capLabel(for seconds: TimeInterval) -> String {
    guard seconds > 0 else { return "No limit" }
    let hours = Int(seconds) / 3600
    return hours == 1 ? "1 hour" : "\(hours) hours"
  }

  private var scheduleStatusText: String {
    let fmt = DateFormatter()
    fmt.timeStyle = .short
    fmt.dateStyle = .none
    switch viewModel.keepAwakeScheduleMode {
    case .startAndEnd:
      return "Will run from \(fmt.string(from: viewModel.keepAwakeScheduleStartTime)) to \(fmt.string(from: viewModel.keepAwakeScheduleEndTime))."
    case .endOnly:
      return "Will start now and end at \(fmt.string(from: viewModel.keepAwakeScheduleEndTime))."
    case .startAndDuration:
      return "Will start at \(fmt.string(from: viewModel.keepAwakeScheduleStartTime)) for \(Int(viewModel.keepAwakeScheduleDurationHours)) hour(s)."
    }
  }
}
