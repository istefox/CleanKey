// TwoZoneSlider.swift
// Pure mapping between a 0...1 slider position and a discrete lock duration.
// No UI imports; safe to use from any context.

import Foundation

struct TwoZoneSlider {
  // 21 discrete durations: 12 short-zone steps (5 s each) + 9 long-zone steps (60 s each).
  // Steps 0–11: 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 s
  // Steps 12–20: 120, 180, 240, 300, 360, 420, 480, 540, 600 s
  static let steps: [TimeInterval] = [
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
    120, 180, 240, 300, 360, 420, 480, 540, 600,
  ]

  // Maps a slider position in 0...1 to a duration.
  // The position is snapped to the nearest 1/20 increment before lookup.
  static func durationForPosition(_ position: Double) -> TimeInterval {
    let clamped = max(0.0, min(1.0, position))
    let index = Int((clamped * 20).rounded())
    return steps[index]
  }

  // Maps a duration to the corresponding slider position in 0...1.
  // Returns the position of the nearest step when the duration falls between steps.
  static func positionForDuration(_ duration: TimeInterval) -> Double {
    var bestIndex = 0
    var bestDistance = abs(steps[0] - duration)
    for i in 1..<steps.count {
      let d = abs(steps[i] - duration)
      if d < bestDistance {
        bestDistance = d
        bestIndex = i
      }
    }
    return Double(bestIndex) / 20.0
  }
}
