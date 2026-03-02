Pod::Spec.new do |s|
  s.name             = 'turbotoken'
  s.version          = '0.1.0'
  s.summary          = 'The fastest BPE tokenizer — Flutter plugin for iOS/macOS.'
  s.description      = <<-DESC
  turbotoken is a drop-in replacement for tiktoken, using Zig + hand-written
  assembly for maximum performance on every platform.
                       DESC
  s.homepage         = 'https://github.com/nicebytes/turbotoken'
  s.license          = { :type => 'MIT' }
  s.author           = { 'nicebytes' => 'hello@nicebytes.com' }
  s.source           = { :git => 'https://github.com/nicebytes/turbotoken.git', :tag => s.version.to_s }

  s.ios.deployment_target = '12.0'
  s.osx.deployment_target = '10.14'

  # The native library is bundled as a vendored framework or dylib.
  s.vendored_libraries = 'libturbotoken.dylib'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-lturbotoken',
  }

  # Dart FFI handles the library loading — no Swift/ObjC source needed.
  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'
  s.swift_version = '5.0'
end
