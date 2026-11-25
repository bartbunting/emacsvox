Pod::Spec.new do |s|
  s.name = 'IphoneTerminal'
  s.version = '0.1.0'
  s.summary = 'Local terminal for an Emacs client over SSH'
  s.homepage = 'https://github.com/bartbunting/emacsvox'
  s.author = 'Emacsvox contributors'
  s.license = 'GPL-2.0-or-later'
  s.source = { :git => 'https://github.com/bartbunting/emacsvox.git' }
  s.platform = :ios, '16.4'
  s.swift_version = '5.9'
  s.static_framework = true
  s.source_files = '*.swift'
  s.dependency 'ExpoModulesCore'
  spm_dependency(s, url: File.expand_path('../../../ssh', __dir__),
                 requirement: {}, products: ['EmacsTerminalSSH'])
  spm_dependency(s, url: 'https://github.com/migueldeicaza/SwiftTerm.git',
                 requirement: {kind: 'exactVersion', version: '1.19.0'}, products: ['SwiftTerm'])
end
