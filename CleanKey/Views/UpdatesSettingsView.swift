import SwiftUI

struct UpdatesSettingsView: View {

  @Bindable var viewModel: SettingsViewModel
  let updateManager: UpdateManager

  var body: some View {
    Form {
      Section("Current Version") {
        LabeledContent("Version", value: currentVersion)
      }

      Section("Automatic Updates") {
        Picker("Check for updates", selection: $viewModel.updateFrequency) {
          ForEach(UpdateCheckFrequency.allCases, id: \.self) { freq in
            Text(label(for: freq)).tag(freq)
          }
        }
        .pickerStyle(.menu)
      }

      Section("Check Now") {
        HStack {
          Button("Check Now") {
            Task { await updateManager.checkNow(userTriggered: true) }
          }
          .disabled(isBusy)

          if case .available(let release) = updateManager.status {
            Button("Download & Install") {
              Task { await updateManager.downloadAndMount(release) }
            }
            .disabled(isBusy)
          }
        }

        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }

  // MARK: - Helpers

  private var currentVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
  }

  private var isBusy: Bool {
    switch updateManager.status {
    case .checking, .downloading, .installing:
      return true
    default:
      return false
    }
  }

  private var statusText: String {
    switch updateManager.status {
    case .idle:
      return "Not checked yet."
    case .checking:
      return "Checking for updates…"
    case .upToDate(let date):
      let fmt = RelativeDateTimeFormatter()
      fmt.unitsStyle = .full
      return "You're up to date. Last checked \(fmt.localizedString(for: date, relativeTo: Date()))."
    case .available(let release):
      return "Version \(release.version) is available."
    case .downloading:
      return "Downloading update…"
    case .installing:
      return "Download complete. Open the mounted disk image to install."
    case .failed(let message):
      return "Check failed: \(message)"
    }
  }

  private func label(for frequency: UpdateCheckFrequency) -> String {
    switch frequency {
    case .daily: return "Daily"
    case .weekly: return "Weekly"
    case .onLaunch: return "On launch only"
    case .never: return "Never (manual only)"
    }
  }
}
