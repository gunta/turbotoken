# Scorecard

Generated: 2026-03-02T18:14:01.859Z

## Comparison (100KB encode)
- turbotoken: 41 ms
- tiktoken: 277.1 ms
- speedup: 6.75x

## Startup ("hello" first encode)
- cold turbotoken: 67.5 ms
- cold tiktoken: 220.7 ms
- cold gpt-tokenizer (Bun): 170.6 ms
- warm turbotoken: 74.3 ms
- warm tiktoken: 228.2 ms
- warm gpt-tokenizer (Bun): 179.5 ms

## WASM (Node + Browser)
- total wasm rows: 15
- node wasm rows: 6
- browser wasm rows: 3
- node row node-wasm-startup-first-encode-hello: 77.14 ms | throughput n/a
- node row node-wasm-startup-first-bpe-encode-hello: 156.62 ms | throughput n/a
- node row node-wasm-encode-utf8-bytes-100kb: 74.55 ms | 1.31 MB/s
- node row node-wasm-encode-utf8-bytes-1mb: 77.75 ms | 12.86 MB/s
- node row node-wasm-encode-bpe-o200k-100kb: 185.76 ms | 0.53 MB/s
- node row node-wasm-encode-bpe-o200k-1mb: 502.18 ms | 1.99 MB/s
- browser row browser-wasm-startup-first-encode-hello: ok | 1.03 ms | throughput n/a
- browser row browser-wasm-encode-utf8-bytes-1mb: ok | 0.3 ms | 3333.33 MB/s
- browser row browser-wasm-encode-bpe-o200k-1mb: ok | 315.4 ms | 3.17 MB/s

## GPU Direct A/B (Headline: normal-text)
- profile count: 4
- headline profile: normal-text
- headline disabled: n/a
- headline enabled: n/a
- headline slowdown: n/a
- headline throughput ratio (enabled/disabled): n/a
- headline route disabled (GPU-only): n/a
- headline route enabled (GPU-only): n/a
- headline route throughput ratio (enabled/disabled): n/a
- stress profile: low-entropy
- stress slowdown: n/a
- stress throughput ratio (enabled/disabled): n/a
- long-lane headline key: normalTextLong
- long-lane bytes: 1,048,576
- long-lane disabled: n/a
- long-lane enabled: n/a
- long-lane slowdown: n/a
- long-lane throughput ratio (enabled/disabled): n/a
- long-lane route disabled (GPU-only): n/a
- long-lane route enabled (GPU-only): n/a
- long-lane route throughput ratio (enabled/disabled): n/a
- long-lane stress key: lowEntropyLong
- long-lane stress slowdown: n/a
- long-lane stress throughput ratio (enabled/disabled): n/a

## GPU Host Overhead
- digest speedup (raw/cached): 11086.58x
- rank table cold init: 1423.061 ms
- rank table warm init: 0.007 ms
- normal-text direct disabled host-overhead: 297.303 ms
- normal-text direct enabled host-overhead: 67.842 ms

## Winners
- encode 100KB: turbotoken
- encode 1MB: turbotoken
- count 1MB: turbotoken
- decode 128K tok: n/a
- chat encode: turbotoken
- chat count: turbotoken
- chat limit: turbotoken
- training 100KB: turbotoken-native
- training 1MB native: turbotoken-native
- training 1MB native latency: 56.7 ms
- training 1MB native throughput: 17.635 MiB/s
- training 1MB native RSS: 18.68 MB

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260302-113906.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260302-113945.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260301-103552.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260302-114054.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260301-171212.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260301-171220.json
- chatHelpers: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-chat-helpers-20260301-103624.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260302-112550.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772450936168.json
- wasm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-wasm-1772455201579.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772469000332.json
- gpuHostOverhead: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-host-overhead-1772475205633.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772453446855.json
- gpuBpeDirect: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-bpe-direct-1772468769516.json

