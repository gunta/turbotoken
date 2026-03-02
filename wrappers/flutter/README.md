# turbotoken Flutter Wrapper

Experimental Flutter plugin for turbotoken using FFI.

## Local Dev

```bash
zig build
cd wrappers/flutter
flutter pub get
flutter test
```

Notes:
- Plugin sources are under `wrappers/flutter/lib/src`.
- Platform glue is in `wrappers/flutter/android` and `wrappers/flutter/ios`.
