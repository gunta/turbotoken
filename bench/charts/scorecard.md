# Scorecard

Generated: 2026-02-27T20:34:37.468Z

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
- gpuMemory: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-memory-1772224066302.json
- gpuOverlap: /Users/a12907/Documents/GitHub/turbotoken/bench/results/bench-gpu-overlap-1772224466624.json

