// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import ExpoModulesCore
import UIKit

private final class DecibelSlider: UISlider {
  override func accessibilityIncrement() { step(1) }
  override func accessibilityDecrement() { step(-1) }

  private func step(_ direction: Float) {
    setValue(value.rounded() + direction, animated: false)
    sendActions(for: .valueChanged)
  }
}

final class PhoneSpeechLoudnessView: ExpoView {
  let onLevelChange = EventDispatcher()
  private let slider = DecibelSlider()
  private var level = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isAccessibilityElement = false
    slider.minimumValue = 0
    slider.maximumValue = 6
    slider.accessibilityLabel = "Speech loudness"
    slider.accessibilityHint = "Adjusts Omnivox speech on this phone. Save settings to apply."
    slider.addTarget(self, action: #selector(changed), for: .valueChanged)
    addSubview(slider)
    setLevel(0)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    slider.frame = bounds.insetBy(dx: 4, dy: 0)
  }

  func setLevel(_ db: Int) {
    level = min(6, max(0, db))
    slider.value = Float(level)
    slider.accessibilityValue = level == 0 ? "Desktop level, zero decibels" : "Plus \(level) decibels"
  }

  @objc private func changed() {
    let previous = level
    setLevel(Int(slider.value.rounded()))
    if level != previous { onLevelChange(["decibels": level]) }
  }
}
