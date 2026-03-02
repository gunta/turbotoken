# turbotoken Ruby Wrapper

Experimental Ruby gem wrapper for turbotoken.

## Local Dev

```bash
zig build
cd wrappers/ruby
bundle install
bundle exec rspec
```

Notes:
- Gem spec: `wrappers/ruby/turbotoken.gemspec`.
- Native calls are routed via Ruby FFI.
