Gem::Specification.new do |s|
  s.name        = "turbotoken"
  s.version     = "0.1.0"
  s.summary     = "The fastest BPE tokenizer on every platform"
  s.description = "Drop-in replacement for tiktoken. Uses Zig + hand-written assembly for peak performance."
  s.authors     = ["TurboToken Contributors"]
  s.license     = "MIT"
  s.homepage    = "https://github.com/turbotoken/turbotoken"
  s.metadata = {
    "homepage_uri" => "https://github.com/turbotoken/turbotoken/tree/main/wrappers/ruby",
    "source_code_uri" => "https://github.com/turbotoken/turbotoken",
    "bug_tracker_uri" => "https://github.com/turbotoken/turbotoken/issues",
    "changelog_uri" => "https://github.com/turbotoken/turbotoken/blob/main/docs/CHANGELOG.md"
  }

  s.files       = Dir["lib/**/*.rb", "LICENSE", "README.md"]
  s.require_paths = ["lib"]

  s.required_ruby_version = ">= 3.0"

  s.add_runtime_dependency "ffi", "~> 1.15"

  s.add_development_dependency "rspec", "~> 3.12"
  s.add_development_dependency "rake", "~> 13.0"
end
