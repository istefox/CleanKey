// TwoZoneSliderTests.swift
// Unit tests for TwoZoneSlider mapping functions.

import XCTest

@testable import CleanKey

final class TwoZoneSliderTests: XCTestCase {

  // MARK: - Boundary values

  func testPositionZeroMapsToMinimumDuration() {
    XCTAssertEqual(TwoZoneSlider.durationForPosition(0.0), 5)
  }

  func testPositionOneMapsToMaximumDuration() {
    XCTAssertEqual(TwoZoneSlider.durationForPosition(1.0), 600)
  }

  // MARK: - Zone boundary

  func testPositionStep11MapsTo60Seconds() {
    // Step 11 (index 11 of 20) is the last short-zone value: 60 s
    let position = 11.0 / 20.0
    XCTAssertEqual(TwoZoneSlider.durationForPosition(position), 60)
  }

  func testPositionStep12MapsTo120Seconds() {
    // Step 12 (index 12 of 20) is the first long-zone value: 120 s
    let position = 12.0 / 20.0
    XCTAssertEqual(TwoZoneSlider.durationForPosition(position), 120)
  }

  // MARK: - Round-trip for all 21 step positions

  func testRoundTripForAllStepPositions() {
    for index in 0...20 {
      let position = Double(index) / 20.0
      let roundTripped = TwoZoneSlider.positionForDuration(
        TwoZoneSlider.durationForPosition(position)
      )
      XCTAssertEqual(
        roundTripped, position, accuracy: 1e-9,
        "Round-trip failed at step \(index)"
      )
    }
  }

  // MARK: - Clamp behavior

  func testPositionBelowZeroClampsToStep0() {
    XCTAssertEqual(TwoZoneSlider.durationForPosition(-0.1), 5)
  }

  func testPositionAboveOneClampsToStep20() {
    XCTAssertEqual(TwoZoneSlider.durationForPosition(1.1), 600)
  }

  // MARK: - All 21 known durations map to the correct step index

  func testAllKnownDurationsMapToCorrectIndex() {
    let expected: [TimeInterval] = [
      5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
      120, 180, 240, 300, 360, 420, 480, 540, 600,
    ]
    for (index, duration) in expected.enumerated() {
      let expectedPosition = Double(index) / 20.0
      let actualPosition = TwoZoneSlider.positionForDuration(duration)
      XCTAssertEqual(
        actualPosition, expectedPosition, accuracy: 1e-9,
        "Duration \(duration) mapped to wrong position"
      )
    }
  }

  // MARK: - Steps array shape

  func testStepsCountIs21() {
    XCTAssertEqual(TwoZoneSlider.steps.count, 21)
  }
}
