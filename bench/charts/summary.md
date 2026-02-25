# Benchmark Summary

Generated: 2026-02-24T15:08:38.243Z

| Source JSON | Command | Mean (ms) |
|-------------|---------|-----------|
| bench-throughput-20260224-134234.json | count-100kb | 65.978 |
| bench-throughput-20260224-145545.json | count-100kb | 147.841 |
| bench-throughput-20260224-150056.json | count-100kb | 148.358 |
| bench-throughput-20260224-150753.json | count-100kb | 149.828 |
| bench-throughput-20260224-134234.json | count-10kb | 69.711 |
| bench-throughput-20260224-145545.json | count-10kb | 141.273 |
| bench-throughput-20260224-150056.json | count-10kb | 142.438 |
| bench-throughput-20260224-150753.json | count-10kb | 140.900 |
| bench-throughput-20260224-134234.json | count-1kb | 67.363 |
| bench-throughput-20260224-145545.json | count-1kb | 141.132 |
| bench-throughput-20260224-150056.json | count-1kb | 147.297 |
| bench-throughput-20260224-150753.json | count-1kb | 139.896 |
| bench-bigfile-20260224-134236.json | encode-1mb | 71.162 |
| bench-bigfile-20260224-145556.json | encode-1mb | 208.891 |
| bench-bigfile-20260224-150108.json | encode-1mb | 203.218 |
| bench-bigfile-20260224-150803.json | encode-1mb | 198.773 |
| bench-startup-20260224-134228.json | python-import-and-first-encode | 73.811 |
| bench-startup-20260224-134324.json | python-import-and-first-encode | 67.519 |
| bench-startup-20260224-145529.json | python-import-and-first-encode | 142.120 |
| bench-startup-20260224-150040.json | python-import-and-first-encode | 137.943 |
| bench-startup-20260224-150737.json | python-import-and-first-encode | 139.340 |
| bench-parallel-20260224-134238.json | threadpool-count-512-items | 79.840 |
| bench-parallel-20260224-145601.json | threadpool-count-512-items | 1529.078 |
| bench-parallel-20260224-150112.json | threadpool-count-512-items | 1555.900 |
| bench-parallel-20260224-150808.json | threadpool-count-512-items | 1569.940 |
| bench-comparison-20260224-145621.json | tiktoken-encode-100kb | 194.052 |
| bench-comparison-20260224-150133.json | tiktoken-encode-100kb | 195.845 |
| bench-comparison-20260224-150829.json | tiktoken-encode-100kb | 195.041 |
| bench-count-20260224-133540.json | turbotoken-count-100kb | 67.442 |
| bench-count-20260224-134037.json | turbotoken-count-100kb | 75.923 |
| bench-count-20260224-134230.json | turbotoken-count-100kb | 67.376 |
| bench-count-20260224-134327.json | turbotoken-count-100kb | 72.128 |
| bench-count-20260224-135330.json | turbotoken-count-100kb | 114.087 |
| bench-count-20260224-145512.json | turbotoken-count-100kb | 145.265 |
| bench-count-20260224-145533.json | turbotoken-count-100kb | 144.367 |
| bench-count-20260224-150044.json | turbotoken-count-100kb | 145.351 |
| bench-count-20260224-150741.json | turbotoken-count-100kb | 144.305 |
| bench-decode-20260224-134232.json | turbotoken-decode-100kb-equivalent | 71.872 |
| bench-decode-20260224-145541.json | turbotoken-decode-100kb-equivalent | 180.135 |
| bench-decode-20260224-150052.json | turbotoken-decode-100kb-equivalent | 180.473 |
| bench-decode-20260224-150749.json | turbotoken-decode-100kb-equivalent | 181.905 |
| bench-comparison-20260224-134239.json | turbotoken-encode-100kb | 68.813 |
| bench-comparison-20260224-145621.json | turbotoken-encode-100kb | 150.394 |
| bench-comparison-20260224-150133.json | turbotoken-encode-100kb | 145.608 |
| bench-comparison-20260224-150829.json | turbotoken-encode-100kb | 147.147 |
| bench-encode-20260224-134231.json | turbotoken-encode-100kb | 67.422 |
| bench-encode-20260224-134329.json | turbotoken-encode-100kb | 70.317 |
| bench-encode-20260224-145537.json | turbotoken-encode-100kb | 147.337 |
| bench-encode-20260224-150048.json | turbotoken-encode-100kb | 143.920 |
| bench-encode-20260224-150745.json | turbotoken-encode-100kb | 148.679 |
| build-all-1771940570553.json | zig build | n/a |
| build-all-1771941588410.json | zig build | n/a |
| build-all-1771945599621.json | zig build | n/a |
| build-all-1771940570553.json | zig build -Dtarget=aarch64-linux | n/a |
| build-all-1771941588410.json | zig build -Dtarget=aarch64-linux | n/a |
| build-all-1771945599621.json | zig build -Dtarget=aarch64-linux | n/a |
| build-all-1771940570553.json | zig build -Dtarget=aarch64-macos | n/a |
| build-all-1771941588410.json | zig build -Dtarget=aarch64-macos | n/a |
| build-all-1771945599621.json | zig build -Dtarget=aarch64-macos | n/a |
| build-all-1771940570553.json | zig build -Dtarget=wasm32-freestanding | n/a |
| build-all-1771941588410.json | zig build -Dtarget=wasm32-freestanding | n/a |
| build-all-1771945599621.json | zig build -Dtarget=wasm32-freestanding | n/a |
| build-all-1771940570553.json | zig build -Dtarget=x86_64-linux | n/a |
| build-all-1771941588410.json | zig build -Dtarget=x86_64-linux | n/a |
| build-all-1771945599621.json | zig build -Dtarget=x86_64-linux | n/a |
| build-all-1771940570553.json | zig build test | n/a |
| build-all-1771941588410.json | zig build test | n/a |
| build-all-1771945599621.json | zig build test | n/a |
