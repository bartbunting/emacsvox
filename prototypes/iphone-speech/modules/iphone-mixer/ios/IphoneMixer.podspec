Pod::Spec.new do |s|
  s.name = 'IphoneMixer'
  s.version = '0.1.0'
  s.summary = 'Foreground Emacsvox speech mixing experiment'
  s.homepage = 'https://github.com/bartbunting/emacsvox'
  s.author = 'Emacsvox contributors'
  s.license = 'GPL-2.0-or-later'
  s.source = { :git => 'https://github.com/bartbunting/emacsvox.git' }
  s.platform = :ios, '16.4'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = '*.swift'
  s.vendored_frameworks = 'OmnivoxMobile.xcframework'
  s.resources = 'OmnivoxSounds.bundle', 'CapitalTiming.json'
  s.dependency 'ExpoModulesCore'
end
