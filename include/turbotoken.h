/**
 * turbotoken.h — C API for turbotoken, the fastest BPE tokenizer.
 *
 * Auto-maintained from src/exports.zig. Do not edit by hand.
 *
 * Error convention:
 *   >= 0  success (count of items written or measured)
 *   -1    error (invalid input, allocation failure, etc.)
 *   -2    limit exceeded (for is_within_token_limit variants)
 *
 * Two-pass allocation pattern:
 *   Pass out_tokens=NULL → returns required size.
 *   Allocate that many elements, call again with the buffer.
 */

#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Version ─────────────────────────────────────────────────────────── */

/** Returns a null-terminated version string (e.g. "0.1.0-dev"). */
const char *turbotoken_version(void);

/* ── Cache management ────────────────────────────────────────────────── */

/** Clear the internal rank table cache. Thread-safe. */
void turbotoken_clear_rank_table_cache(void);

/* ── WASM helpers (wasm32 only) ──────────────────────────────────────── */

/** Allocate memory in WASM linear memory. Returns NULL on failure. */
uint8_t *turbotoken_wasm_alloc(size_t size);

/** Free a WASM allocation returned by turbotoken_wasm_alloc. */
void turbotoken_wasm_free(uint8_t *ptr, size_t size);

/* ── Basic byte-level operations ─────────────────────────────────────── */

/** Placeholder count — returns text_len as-is. */
ptrdiff_t turbotoken_count(const uint8_t *text, size_t text_len);

/* ── Pretokenizer (range splitting) ──────────────────────────────────── */

/**
 * Split ASCII text into letter/space ranges.
 * Pass out_starts=NULL to query needed capacity.
 */
ptrdiff_t turbotoken_pretokenize_ascii_letter_space_ranges(
    const uint8_t *text, size_t text_len,
    uint32_t *out_starts, uint32_t *out_ends, size_t out_cap);

/**
 * Split ASCII text using o200k-compatible regex ranges.
 * Pass out_starts=NULL to query needed capacity.
 */
ptrdiff_t turbotoken_pretokenize_ascii_o200k_ranges(
    const uint8_t *text, size_t text_len,
    uint32_t *out_starts, uint32_t *out_ends, size_t out_cap);

/* ── Architecture introspection ──────────────────────────────────────── */

/** Returns ARM64 feature bitmask (0 on non-ARM64). */
uint64_t turbotoken_arm64_feature_mask(void);

/** Returns kernel ID used for non-ASCII counting (0=scalar). */
uint32_t turbotoken_count_non_ascii_kernel_id(void);

/* ── UTF-8 byte-level counting ───────────────────────────────────────── */

/** Count non-ASCII UTF-8 bytes using best available kernel. */
ptrdiff_t turbotoken_count_non_ascii_utf8(
    const uint8_t *text, size_t text_len);

/** Count non-ASCII UTF-8 bytes using scalar fallback. */
ptrdiff_t turbotoken_count_non_ascii_utf8_scalar(
    const uint8_t *text, size_t text_len);

/** Count non-ASCII UTF-8 bytes using NEON (ARM64 only). */
ptrdiff_t turbotoken_count_non_ascii_utf8_neon(
    const uint8_t *text, size_t text_len);

/** Count non-ASCII UTF-8 bytes using dot-product (ARM64 only). */
ptrdiff_t turbotoken_count_non_ascii_utf8_dotprod(
    const uint8_t *text, size_t text_len);

/** Count non-ASCII UTF-8 bytes using SME (ARM64 only). */
ptrdiff_t turbotoken_count_non_ascii_utf8_sme(
    const uint8_t *text, size_t text_len);

/* ── ASCII class boundary counting ───────────────────────────────────── */

/** Count ASCII class boundaries using best available kernel. */
ptrdiff_t turbotoken_count_ascii_class_boundaries_utf8(
    const uint8_t *text, size_t text_len);

/** Count ASCII class boundaries using scalar fallback. */
ptrdiff_t turbotoken_count_ascii_class_boundaries_utf8_scalar(
    const uint8_t *text, size_t text_len);

/** Count ASCII class boundaries using NEON (ARM64 only). */
ptrdiff_t turbotoken_count_ascii_class_boundaries_utf8_neon(
    const uint8_t *text, size_t text_len);

/* ── UTF-8 byte encode/decode ────────────────────────────────────────── */

/**
 * Encode UTF-8 bytes to u32 tokens (one byte per token).
 * Pass out_tokens=NULL to query needed capacity (returns text_len).
 */
ptrdiff_t turbotoken_encode_utf8_bytes(
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

/** Scalar variant of turbotoken_encode_utf8_bytes. */
ptrdiff_t turbotoken_encode_utf8_bytes_scalar(
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

/**
 * Decode u32 byte-tokens back to UTF-8 bytes.
 * Pass out_bytes=NULL to query needed capacity (returns token_len).
 */
ptrdiff_t turbotoken_decode_utf8_bytes(
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

/** Scalar variant of turbotoken_decode_utf8_bytes. */
ptrdiff_t turbotoken_decode_utf8_bytes_scalar(
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

/* ── BPE encode / decode / count (rank-table based) ──────────────────── */

/**
 * BPE-encode text using a preloaded rank table.
 * Pass out_tokens=NULL to query needed capacity.
 *
 * @param rank_bytes  Raw rank file bytes (base64 tiktoken format or native binary)
 * @param rank_len    Length of rank_bytes
 * @param text        UTF-8 input text
 * @param text_len    Length of text in bytes
 * @param out_tokens  Output buffer for token IDs (or NULL for size query)
 * @param out_cap     Capacity of out_tokens
 * @return            Number of tokens written, or -1 on error
 */
ptrdiff_t turbotoken_encode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

/**
 * BPE-decode token IDs back to UTF-8 bytes using a rank table.
 * Pass out_bytes=NULL to query needed capacity.
 */
ptrdiff_t turbotoken_decode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

/**
 * Count BPE tokens for text without materializing token array.
 */
ptrdiff_t turbotoken_count_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len);

/**
 * Check if text is within a token limit.
 * Returns token count if within limit, -2 if exceeded, -1 on error.
 */
ptrdiff_t turbotoken_is_within_token_limit_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    size_t token_limit);

/* ── BPE file operations ─────────────────────────────────────────────── */

/**
 * BPE-encode a file's contents. Pass out_tokens=NULL for size query.
 *
 * @param file_path      Null-free UTF-8 file path
 * @param file_path_len  Length of file_path
 */
ptrdiff_t turbotoken_encode_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    uint32_t *out_tokens, size_t out_cap);

/** Count BPE tokens in a file without materializing token array. */
ptrdiff_t turbotoken_count_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len);

/**
 * Check if a file's content is within a token limit.
 * Returns token count if within limit, -2 if exceeded, -1 on error.
 */
ptrdiff_t turbotoken_is_within_token_limit_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    size_t token_limit);

/* ── Batch / range BPE encode ────────────────────────────────────────── */

/**
 * BPE-encode multiple text segments defined by contiguous offsets.
 * offsets[0..offsets_len] define segments: text[offsets[i]..offsets[i+1]].
 * out_token_offsets (optional) receives per-segment token offset indices.
 */
ptrdiff_t turbotoken_encode_bpe_batch_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    const uint32_t *offsets, size_t offsets_len,
    uint32_t *out_tokens, size_t out_cap,
    uint32_t *out_token_offsets, size_t out_token_offsets_len);

/**
 * BPE-encode multiple text ranges defined by separate start/end arrays.
 */
ptrdiff_t turbotoken_encode_bpe_ranges_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    const uint32_t *range_starts, const uint32_t *range_ends,
    size_t ranges_len,
    uint32_t *out_tokens, size_t out_cap,
    uint32_t *out_token_offsets, size_t out_token_offsets_len);

/**
 * Compute token layout metadata for pre-encoded BPE ranges.
 * Used for GPU overlap / chunked encoding pipelines.
 */
ptrdiff_t turbotoken_bpe_ranges_token_layout_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    size_t input_len,
    const uint32_t *range_starts, const uint32_t *range_ends,
    size_t ranges_len,
    const uint32_t *tokens, size_t token_len,
    const uint32_t *token_offsets, size_t token_offsets_len,
    uint32_t source_chunk_base, uint32_t chunk_bytes, uint32_t num_chunks,
    uint32_t *out_token_starts, uint32_t *out_source_chunks, size_t out_cap);

/**
 * Filter tokens by a parallel keep-flags array.
 * Pass out_tokens=NULL to query the count of kept tokens.
 */
ptrdiff_t turbotoken_filter_tokens_by_keep_flags(
    const uint32_t *tokens, const uint32_t *keep_flags, size_t token_len,
    uint32_t *out_tokens, size_t out_cap);

/**
 * BPE-encode text in overlapping chunks and stitch the results.
 * Pass out_tokens=NULL for size query.
 */
ptrdiff_t turbotoken_encode_bpe_chunked_stitched_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    size_t chunk_bytes, size_t overlap_bytes,
    uint32_t *out_tokens, size_t out_cap);

/* ── Specialized ASCII BPE paths ─────────────────────────────────────── */

/** Count BPE tokens using o200k-specific ASCII pretokenizer. */
ptrdiff_t turbotoken_count_bpe_ascii_o200k_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len);

/** Count BPE tokens using letter/space ASCII pretokenizer. */
ptrdiff_t turbotoken_count_bpe_ascii_letter_space_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len);

/**
 * BPE-encode using letter/space ASCII pretokenizer.
 * Pass out_tokens=NULL for size query.
 */
ptrdiff_t turbotoken_encode_bpe_ascii_letter_space_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

/**
 * BPE-encode using o200k-specific ASCII pretokenizer.
 * Pass out_tokens=NULL for size query.
 */
ptrdiff_t turbotoken_encode_bpe_ascii_o200k_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

/* ── BPE training ────────────────────────────────────────────────────── */

/**
 * Train BPE merges from pre-chunked text with counts.
 * Each merge is 2 x u32 (pair token IDs) packed into out_merges.
 * Pass out_merges=NULL for size query.
 *
 * @param chunks            Concatenated chunk bytes
 * @param chunks_len        Total length of chunks
 * @param chunk_offsets     Offsets array (length = chunk_counts_len + 1)
 * @param chunk_offsets_len Length of chunk_offsets
 * @param chunk_counts      Frequency of each chunk
 * @param chunk_counts_len  Number of chunks
 * @param vocab_size        Target vocabulary size (must be >= 256)
 * @param min_frequency     Minimum pair frequency to merge (must be >= 1)
 * @param out_merges        Output buffer for merge pairs (2 u32 per merge)
 * @param out_cap           Capacity of out_merges in u32 elements
 */
ptrdiff_t turbotoken_train_bpe_from_chunk_counts(
    const uint8_t *chunks, size_t chunks_len,
    const uint32_t *chunk_offsets, size_t chunk_offsets_len,
    const uint32_t *chunk_counts, size_t chunk_counts_len,
    uint32_t vocab_size, uint32_t min_frequency,
    uint32_t *out_merges, size_t out_cap);

/**
 * Train BPE on a single ASCII text using o200k pretokenizer.
 */
ptrdiff_t turbotoken_train_bpe_ascii_o200k(
    const uint8_t *text, size_t text_len,
    uint32_t vocab_size, uint32_t min_frequency,
    uint32_t *out_merges, size_t out_cap);

/**
 * Train BPE on multiple texts (concatenated with offsets) using o200k pretokenizer.
 */
ptrdiff_t turbotoken_train_bpe_ascii_o200k_multi(
    const uint8_t *texts, size_t texts_len,
    const uint32_t *text_offsets, size_t text_offsets_len,
    uint32_t vocab_size, uint32_t min_frequency,
    uint32_t *out_merges, size_t out_cap);

#ifdef __cplusplus
}
#endif
