module TurboToken.Native

open System
open System.Runtime.InteropServices

[<Literal>]
let private LibName = "turbotoken"

// Version
[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_version()

// Cache
[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern void turbotoken_clear_rank_table_cache()

// BPE encode/decode/count (rank-table based)
[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_encode_bpe_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint text, unativeint text_len,
    nativeint out_tokens, unativeint out_cap)

[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_decode_bpe_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint tokens, unativeint token_len,
    nativeint out_bytes, unativeint out_cap)

[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_count_bpe_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint text, unativeint text_len)

[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_is_within_token_limit_bpe_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint text, unativeint text_len,
    unativeint token_limit)

// BPE file operations
[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_encode_bpe_file_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint file_path, unativeint file_path_len,
    nativeint out_tokens, unativeint out_cap)

[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_count_bpe_file_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint file_path, unativeint file_path_len)

[<DllImport(LibName, CallingConvention = CallingConvention.Cdecl)>]
extern nativeint turbotoken_is_within_token_limit_bpe_file_from_ranks(
    nativeint rank_bytes, unativeint rank_len,
    nativeint file_path, unativeint file_path_len,
    unativeint token_limit)
