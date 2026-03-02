//! Hand-written extern "C" declarations for turbotoken's C ABI.
//!
//! These match the signatures in `include/turbotoken.h`.

use std::os::raw::c_char;

extern "C" {
    /// Returns a null-terminated version string (e.g. "0.1.0-dev").
    pub fn turbotoken_version() -> *const c_char;

    /// Clear the internal rank table cache. Thread-safe.
    pub fn turbotoken_clear_rank_table_cache();

    /// BPE-encode text using a preloaded rank table.
    /// Pass out_tokens=NULL to query needed capacity.
    pub fn turbotoken_encode_bpe_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        text: *const u8,
        text_len: usize,
        out_tokens: *mut u32,
        out_cap: usize,
    ) -> isize;

    /// BPE-decode token IDs back to UTF-8 bytes using a rank table.
    /// Pass out_bytes=NULL to query needed capacity.
    pub fn turbotoken_decode_bpe_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        tokens: *const u32,
        token_len: usize,
        out_bytes: *mut u8,
        out_cap: usize,
    ) -> isize;

    /// Count BPE tokens for text without materializing token array.
    pub fn turbotoken_count_bpe_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        text: *const u8,
        text_len: usize,
    ) -> isize;

    /// Check if text is within a token limit.
    /// Returns token count if within limit, -2 if exceeded, -1 on error.
    pub fn turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        text: *const u8,
        text_len: usize,
        token_limit: usize,
    ) -> isize;

    /// BPE-encode a file's contents. Pass out_tokens=NULL for size query.
    pub fn turbotoken_encode_bpe_file_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        file_path: *const u8,
        file_path_len: usize,
        out_tokens: *mut u32,
        out_cap: usize,
    ) -> isize;

    /// Count BPE tokens in a file without materializing token array.
    pub fn turbotoken_count_bpe_file_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        file_path: *const u8,
        file_path_len: usize,
    ) -> isize;

    /// Check if a file's content is within a token limit.
    /// Returns token count if within limit, -2 if exceeded, -1 on error.
    pub fn turbotoken_is_within_token_limit_bpe_file_from_ranks(
        rank_bytes: *const u8,
        rank_len: usize,
        file_path: *const u8,
        file_path_len: usize,
        token_limit: usize,
    ) -> isize;

    /// Train BPE merges from pre-chunked text with counts.
    /// Pass out_merges=NULL for size query.
    pub fn turbotoken_train_bpe_from_chunk_counts(
        chunks: *const u8,
        chunks_len: usize,
        chunk_offsets: *const u32,
        chunk_offsets_len: usize,
        chunk_counts: *const u32,
        chunk_counts_len: usize,
        vocab_size: u32,
        min_frequency: u32,
        out_merges: *mut u32,
        out_cap: usize,
    ) -> isize;
}
