// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVKit
import ExpoModulesCore

final class PhoneAudioRouteView: ExpoView {
  private let picker = AVRoutePickerView()

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isAccessibilityElement = false
    picker.tintColor = .white
    picker.activeTintColor = .systemBlue
    addSubview(picker)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    picker.frame = bounds
  }
}
