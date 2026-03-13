require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = 'NitroGkPhotoBrowser'
  s.version      = package['version']
  s.summary      = package['description']
  s.homepage     = 'https://example.invalid/react-native-gk-photo-browser'
  s.license      = package['license']
  s.authors      = { 'apple' => 'apple@example.invalid' }
  s.platforms    = { :ios => min_ios_version_supported, :visionos => 1.0 }
  s.source       = { :git => 'https://example.invalid/react-native-gk-photo-browser.git', :tag => s.version.to_s }

  s.source_files = [
    'ios/**/*.{h,m,mm}',
    'cpp/**/*.{h,hpp,c,cpp,mm}'
  ]

  load 'nitrogen/generated/ios/NitroGkPhotoBrowser+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'GKPhotoBrowser/Cover'
  s.dependency 'GKPhotoBrowser/SD'
  s.dependency 'GKPhotoBrowser/AVPlayer'
  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)
end
