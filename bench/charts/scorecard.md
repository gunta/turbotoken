# Scorecard

Generated: 2026-03-01T04:47:11.080Z

## Comparison (100KB encode)
- turbotoken: 44.9 ms
- tiktoken: 216.5 ms
- speedup: 4.82x

## Startup ("hello" first encode)
- cold turbotoken: 69.7 ms
- cold tiktoken: 208.6 ms
- cold gpt-tokenizer (Bun): 158.4 ms
- warm turbotoken: 66.4 ms
- warm tiktoken: 211.8 ms
- warm gpt-tokenizer (Bun): 159.2 ms

## WASM (Node + Browser)
- total wasm rows: 15
- node wasm rows: 6
- browser wasm rows: 3
- node row node-wasm-startup-first-encode-hello: 71.37 ms | throughput n/a
- node row node-wasm-startup-first-bpe-encode-hello: 149.56 ms | throughput n/a
- node row node-wasm-encode-utf8-bytes-100kb: 73.3 ms | 1.33 MB/s
- node row node-wasm-encode-utf8-bytes-1mb: 85.35 ms | 11.72 MB/s
- node row node-wasm-encode-bpe-o200k-100kb: 161.95 ms | 0.6 MB/s
- node row node-wasm-encode-bpe-o200k-1mb: 467.89 ms | 2.14 MB/s
- browser row browser-wasm-startup-first-encode-hello: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-utf8-bytes-1mb: not-run (browser benchmark harness is not configured in this local run)
- browser row browser-wasm-encode-bpe-o200k-1mb: not-run (browser benchmark harness is not configured in this local run)

## Winners
- encode 100KB: turbotoken
- encode 1MB: turbotoken
- count 1MB: turbotoken
- decode 128K tok: turbotoken
- chat encode: turbotoken
- chat count: turbotoken
- chat limit: turbotoken
- training 100KB: turbotoken-python

## Artifacts
- startupCold: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-cold-20260227-170257.json
- startupWarm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-startup-warm-20260227-170333.json
- comparison: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-comparison-20260227-162050.json
- competitorsEncode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-encode-20260227-170426.json
- competitorsDecode: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-decode-20260227-170602.json
- competitorsCount: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-competitors-python-count-20260227-170704.json
- chatHelpers: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-chat-helpers-20260227-174446.json
- training: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-training-python-20260227-145645.json
- ram: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-ram-1772212098947.json
- wasm: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-wasm-1772340365937.json
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772340185487.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772340365580.json
- gpuBpeDirect: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-bpe-direct-1772340364617.json

