# Benchmark Summary

Generated: 2026-02-24T13:43:30.230Z

| Source JSON | Command | Mean (ms) |
|-------------|---------|-----------|
| bench-throughput-20260224-134234.json | count-100kb | 65.978 |
| bench-throughput-20260224-134234.json | count-10kb | 69.711 |
| bench-throughput-20260224-134234.json | count-1kb | 67.363 |
| bench-bigfile-20260224-134236.json | encode-1mb | 71.162 |
| bench-startup-20260224-134228.json | python-import-and-first-encode | 73.811 |
| bench-startup-20260224-134324.json | python-import-and-first-encode | 67.519 |
| bench-parallel-20260224-134238.json | threadpool-count-512-items | 79.840 |
| bench-count-20260224-133540.json | turbotoken-count-100kb | 67.442 |
| bench-count-20260224-134037.json | turbotoken-count-100kb | 75.923 |
| bench-count-20260224-134230.json | turbotoken-count-100kb | 67.376 |
| bench-count-20260224-134327.json | turbotoken-count-100kb | 72.128 |
| bench-decode-20260224-134232.json | turbotoken-decode-100kb-equivalent | 71.872 |
| bench-comparison-20260224-134239.json | turbotoken-encode-100kb | 68.813 |
| bench-encode-20260224-134231.json | turbotoken-encode-100kb | 67.422 |
| bench-encode-20260224-134329.json | turbotoken-encode-100kb | 70.317 |
| build-all-1771940570553.json | zig build | n/a |
| build-all-1771940570553.json | zig build -Dtarget=aarch64-linux | n/a |
| build-all-1771940570553.json | zig build -Dtarget=aarch64-macos | n/a |
| build-all-1771940570553.json | zig build -Dtarget=wasm32-freestanding | n/a |
| build-all-1771940570553.json | zig build -Dtarget=x86_64-linux | n/a |
| build-all-1771940570553.json | zig build test | n/a |
