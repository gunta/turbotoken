# turbotoken C Package

C distribution package for **turbotoken** -- the fastest BPE tokenizer on every platform.

The core C API is defined in `include/turbotoken.h`. This package provides CMake/pkg-config integration, examples, and tests.

## Prerequisites

Build the native library first from the repository root:

```bash
zig build -Doptimize=ReleaseFast
```

This produces `zig-out/lib/libturbotoken.a` (or `.so`/`.dylib` depending on configuration).

## Building with CMake

```bash
cd wrappers/c
mkdir build && cd build

# Option A: use pre-built library (run `zig build` first)
cmake ..

# Option B: build from Zig source automatically
cmake .. -DTURBOTOKEN_BUILD_FROM_SOURCE=ON

cmake --build .
```

## Building with pkg-config

After installing (or pointing `PKG_CONFIG_PATH` to the build directory):

```bash
cc -o encode_example examples/encode_example.c $(pkg-config --cflags --libs turbotoken)
```

## Manual compilation

```bash
cc -I../../include -o encode_example examples/encode_example.c -L../../zig-out/lib -lturbotoken
```

## Quick start

```c
#include "turbotoken.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    /* Load a rank file (e.g. cl100k_base.tiktoken) */
    FILE *f = fopen("cl100k_base.tiktoken", "rb");
    fseek(f, 0, SEEK_END);
    size_t rank_len = (size_t)ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *rank_bytes = malloc(rank_len);
    fread(rank_bytes, 1, rank_len, f);
    fclose(f);

    const char *text = "hello world";

    /* Two-pass pattern: query size, then encode */
    ptrdiff_t n = turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, strlen(text),
        NULL, 0);

    uint32_t *tokens = malloc(sizeof(uint32_t) * (size_t)n);
    turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        (const uint8_t *)text, strlen(text),
        tokens, (size_t)n);

    printf("Tokens: %td\n", n);
    free(tokens);
    free(rank_bytes);
    return 0;
}
```

## API reference

See `include/turbotoken.h` for the complete API. Key functions:

| Function | Description |
|----------|-------------|
| `turbotoken_version()` | Returns version string |
| `turbotoken_encode_bpe_from_ranks()` | BPE encode text to tokens |
| `turbotoken_decode_bpe_from_ranks()` | BPE decode tokens to text |
| `turbotoken_count_bpe_from_ranks()` | Count tokens without encoding |
| `turbotoken_is_within_token_limit_bpe_from_ranks()` | Check if text fits in token limit |
| `turbotoken_encode_bpe_file_from_ranks()` | Encode a file's contents |
| `turbotoken_count_bpe_file_from_ranks()` | Count tokens in a file |

### Error convention

- `>= 0`: success (count of items written or measured)
- `-1`: error (invalid input, allocation failure, etc.)
- `-2`: limit exceeded (for `is_within_token_limit` variants)

### Two-pass allocation pattern

Pass `out_tokens = NULL` to query the required buffer size, then allocate and call again:

```c
ptrdiff_t n = turbotoken_encode_bpe_from_ranks(ranks, len, text, text_len, NULL, 0);
uint32_t *tokens = malloc(sizeof(uint32_t) * n);
turbotoken_encode_bpe_from_ranks(ranks, len, text, text_len, tokens, n);
```

## Running tests

```bash
cd build
TURBOTOKEN_RANK_FILE=/path/to/cl100k_base.tiktoken ctest
```

## Publish

This package is tracked in `wrappers/release-matrix.json`.

From repo root:

```bash
bun run release:check
bun run release:dry-run
```

Then run the ecosystem-specific publish command from `docs/PUBLISHING.md`.
