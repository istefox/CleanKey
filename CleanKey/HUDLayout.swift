import CoreGraphics

/// Pure geometry helper for HUD panel placement.
/// All inputs and outputs are in screen coordinates (points).
/// No AppKit dependency — fully testable without a display.

func hudPanelFrame(
  for screen: CGRect,
  corner: HUDCorner,
  inset: CGFloat = 20,
  size: CGSize = CGSize(width: 200, height: 80)
) -> CGRect {
  let x: CGFloat
  let y: CGFloat

  switch corner {
  case .topLeft:
    x = screen.minX + inset
    y = screen.maxY - size.height - inset
  case .topRight:
    x = screen.maxX - size.width - inset
    y = screen.maxY - size.height - inset
  case .bottomRight:
    x = screen.maxX - size.width - inset
    y = screen.minY + inset
  case .bottomLeft:
    x = screen.minX + inset
    y = screen.minY + inset
  }

  return CGRect(x: x, y: y, width: size.width, height: size.height)
}
