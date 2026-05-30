import CoreGraphics
import XCTest

@testable import CleanKey

final class HUDLayoutTests: XCTestCase {

  private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  private let inset: CGFloat = 20
  private let panelW: CGFloat = 200
  private let panelH: CGFloat = 80

  func testBottomRight() {
    let frame = hudPanelFrame(for: screen, corner: .bottomRight, inset: inset)
    XCTAssertEqual(frame.origin.x, screen.maxX - panelW - inset)
    XCTAssertEqual(frame.origin.y, screen.minY + inset)
    XCTAssertEqual(frame.size.width, panelW)
    XCTAssertEqual(frame.size.height, panelH)
  }

  func testBottomLeft() {
    let frame = hudPanelFrame(for: screen, corner: .bottomLeft, inset: inset)
    XCTAssertEqual(frame.origin.x, screen.minX + inset)
    XCTAssertEqual(frame.origin.y, screen.minY + inset)
  }

  func testTopLeft() {
    let frame = hudPanelFrame(for: screen, corner: .topLeft, inset: inset)
    XCTAssertEqual(frame.origin.x, screen.minX + inset)
    XCTAssertEqual(frame.origin.y, screen.maxY - panelH - inset)
  }

  func testTopRight() {
    let frame = hudPanelFrame(for: screen, corner: .topRight, inset: inset)
    XCTAssertEqual(frame.origin.x, screen.maxX - panelW - inset)
    XCTAssertEqual(frame.origin.y, screen.maxY - panelH - inset)
  }

  // Non-zero screen origin simulates an external display offset.
  func testNonZeroOriginBottomRight() {
    let external = CGRect(x: 1440, y: -200, width: 2560, height: 1440)
    let frame = hudPanelFrame(for: external, corner: .bottomRight, inset: inset)
    XCTAssertEqual(frame.origin.x, external.maxX - panelW - inset)
    XCTAssertEqual(frame.origin.y, external.minY + inset)
  }

  func testNonZeroOriginTopLeft() {
    let external = CGRect(x: -1280, y: 100, width: 1280, height: 800)
    let frame = hudPanelFrame(for: external, corner: .topLeft, inset: inset)
    XCTAssertEqual(frame.origin.x, external.minX + inset)
    XCTAssertEqual(frame.origin.y, external.maxY - panelH - inset)
  }

  func testCustomInset() {
    let frame = hudPanelFrame(for: screen, corner: .bottomLeft, inset: 8)
    XCTAssertEqual(frame.origin.x, screen.minX + 8)
    XCTAssertEqual(frame.origin.y, screen.minY + 8)
  }
}
