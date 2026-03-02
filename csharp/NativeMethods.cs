using System;
using System.Runtime.InteropServices;

namespace TurboToken
{
    internal static class NativeMethods
    {
        private const string LibName = "turbotoken";

        // ── Version ──

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_version();

        // ── Cache ──

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern void turbotoken_clear_rank_table_cache();

        // ── BPE encode/decode/count (rank-table based) ──

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_encode_bpe_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr text, UIntPtr text_len,
            IntPtr out_tokens, UIntPtr out_cap);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_decode_bpe_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr tokens, UIntPtr token_len,
            IntPtr out_bytes, UIntPtr out_cap);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_count_bpe_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr text, UIntPtr text_len);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_is_within_token_limit_bpe_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr text, UIntPtr text_len,
            UIntPtr token_limit);

        // ── BPE file operations ──

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_encode_bpe_file_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr file_path, UIntPtr file_path_len,
            IntPtr out_tokens, UIntPtr out_cap);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_count_bpe_file_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr file_path, UIntPtr file_path_len);

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_is_within_token_limit_bpe_file_from_ranks(
            IntPtr rank_bytes, UIntPtr rank_len,
            IntPtr file_path, UIntPtr file_path_len,
            UIntPtr token_limit);

        // ── BPE training ──

        [DllImport(LibName, CallingConvention = CallingConvention.Cdecl)]
        internal static extern IntPtr turbotoken_train_bpe_from_chunk_counts(
            IntPtr chunks, UIntPtr chunks_len,
            IntPtr chunk_offsets, UIntPtr chunk_offsets_len,
            IntPtr chunk_counts, UIntPtr chunk_counts_len,
            uint vocab_size, uint min_frequency,
            IntPtr out_merges, UIntPtr out_cap);
    }
}
