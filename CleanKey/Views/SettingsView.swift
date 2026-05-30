import SwiftUI

enum SettingsSidebarItem: String, CaseIterable, Identifiable {
  case general = "General"
  case display = "Display"

  var id: String { rawValue }
}

struct SettingsView: View {

  @State private var selection: SettingsSidebarItem? = .general
  let viewModel: SettingsViewModel
  let onSave: () -> Void
  let onCancel: () -> Void

  var body: some View {
    NavigationSplitView {
      List(SettingsSidebarItem.allCases, selection: $selection) { item in
        Label(item.rawValue, systemImage: systemImage(for: item))
          .tag(item)
      }
      .navigationSplitViewColumnWidth(min: 140, ideal: 160)
    } detail: {
      Group {
        switch selection {
        case .general, .none:
          GeneralSettingsView(viewModel: viewModel)
        case .display:
          DisplaySettingsView(viewModel: viewModel)
        }
      }
      .safeAreaInset(edge: .bottom) {
        HStack {
          Spacer()
          Button("Cancel") { onCancel() }
            .keyboardShortcut(.cancelAction)
          Button("Save") { onSave() }
            .keyboardShortcut(.defaultAction)
        }
        .padding()
      }
    }
    .frame(minWidth: 480, minHeight: 320)
  }

  private func systemImage(for item: SettingsSidebarItem) -> String {
    switch item {
    case .general: return "gearshape"
    case .display: return "display"
    }
  }
}
