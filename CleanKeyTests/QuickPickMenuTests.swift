// QuickPickMenuTests.swift
// Unit tests for QuickPickMenuViewModel menu item generation.

import XCTest

@testable import CleanKey

final class QuickPickMenuTests: XCTestCase {

  // MARK: - Helpers

  private func makeSettings(lastDuration: TimeInterval) -> LockSettings {
    var settings = LockSettings(defaults: UserDefaults(suiteName: "QuickPickMenuTests-\(UUID())")!)
    settings.lastDuration = lastDuration
    return settings
  }

  // MARK: - Fixed presets always present

  func testFixedPresetsAlwaysInclude15s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 120))
    XCTAssertTrue(items.contains { $0.duration == 15 })
  }

  func testFixedPresetsAlwaysInclude30s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 120))
    XCTAssertTrue(items.contains { $0.duration == 30 })
  }

  func testFixedPresetsAlwaysInclude60s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 120))
    XCTAssertTrue(items.contains { $0.duration == 60 })
  }

  func testFixedPresetsAlwaysInclude120s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 120))
    XCTAssertTrue(items.contains { $0.duration == 120 })
  }

  // MARK: - No fifth item when default matches a fixed preset

  func testNoFifthItemWhenDefaultIs120s() {
    // 120 s = "2 min", matches the 4th fixed preset.
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 120))
    XCTAssertEqual(items.count, 4)
  }

  func testNoFifthItemWhenDefaultIs15s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 15))
    XCTAssertEqual(items.count, 4)
  }

  func testNoFifthItemWhenDefaultIs30s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 30))
    XCTAssertEqual(items.count, 4)
  }

  func testNoFifthItemWhenDefaultIs60s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 60))
    XCTAssertEqual(items.count, 4)
  }

  // MARK: - Fifth item appears when default differs from all fixed presets

  func testFifthItemAppearsWhenDefaultIs150s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 150))
    XCTAssertEqual(items.count, 5)
  }

  func testFifthItemAppearsWhenDefaultIs5s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 5))
    XCTAssertEqual(items.count, 5)
  }

  // MARK: - Fifth item label contains "(default)"

  func testFifthItemLabelContainsDefaultSuffix() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 150))
    let fifth = items.first { !QuickPickMenuViewModel.fixedPresets.contains($0.duration) }
    XCTAssertNotNil(fifth)
    XCTAssertTrue(
      fifth!.label.hasSuffix("(default)"),
      "Expected label ending in '(default)', got '\(fifth!.label)'")
  }

  func testFifthItemLabelFor150s() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 150))
    let fifth = items.first { $0.duration == 150 }
    XCTAssertEqual(fifth?.label, "2 min 30 s (default)")
  }

  func testFifthItemDurationMatchesDefault() {
    let items = QuickPickMenuViewModel.menuItems(for: makeSettings(lastDuration: 150))
    XCTAssertTrue(items.contains { $0.duration == 150 })
  }
}
