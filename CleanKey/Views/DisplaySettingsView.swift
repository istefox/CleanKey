import SwiftUI

struct DisplaySettingsView: View {

  @Bindable var viewModel: SettingsViewModel

  var body: some View {
    Form {
      Section("Overlay Mode") {
        Picker("Overlay Mode", selection: $viewModel.overlayMode) {
          Text("Black Screen").tag(OverlayMode.blackScreen)
          Text("HUD Only").tag(OverlayMode.hud)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      Section("HUD Corner") {
        HUDCornerPicker(selection: $viewModel.hudCorner)
          .disabled(viewModel.overlayMode == .blackScreen)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// 2x2 grid picker for HUDCorner.
private struct HUDCornerPicker: View {

  @Binding var selection: HUDCorner

  var body: some View {
    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
      GridRow {
        cornerButton(.topLeft, label: "TL")
        cornerButton(.topRight, label: "TR")
      }
      GridRow {
        cornerButton(.bottomLeft, label: "BL")
        cornerButton(.bottomRight, label: "BR")
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private func cornerButton(_ corner: HUDCorner, label: String) -> some View {
    Button(label) {
      selection = corner
    }
    .buttonStyle(.bordered)
    .background(selection == corner ? Color.accentColor.opacity(0.2) : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
