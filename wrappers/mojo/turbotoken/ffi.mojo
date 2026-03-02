from sys.ffi import DLHandle, external_call
from sys.info import os_is_linux, os_is_macos, os_is_windows
from memory import UnsafePointer


fn _lib_name() -> String:
    @parameter
    if os_is_macos():
        return "libturbotoken.dylib"
    elif os_is_windows():
        return "turbotoken.dll"
    else:
        return "libturbotoken.so"


var _handle: DLHandle = DLHandle(_lib_name())


fn load_library() -> DLHandle:
    return _handle


fn ffi_version() -> String:
    var h = load_library()
    var func = h.get_function[fn () -> UnsafePointer[UInt8]]("turbotoken_version")
    var ptr = func()
    if not ptr:
        return "unknown"
    # Read null-terminated C string
    var result = String("")
    var i = 0
    while ptr[i] != 0:
        result += chr(int(ptr[i]))
        i += 1
    return result


fn ffi_clear_cache():
    var h = load_library()
    var func = h.get_function[fn () -> None]("turbotoken_clear_rank_table_cache")
    func()


fn ffi_encode_bpe(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    text: UnsafePointer[UInt8],
    text_len: Int,
    out: UnsafePointer[UInt32],
    out_cap: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt32], Int,
        ) -> Int
    ]("turbotoken_encode_bpe_from_ranks")
    return func(rank_bytes, rank_len, text, text_len, out, out_cap)


fn ffi_decode_bpe(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    tokens: UnsafePointer[UInt32],
    token_len: Int,
    out: UnsafePointer[UInt8],
    out_cap: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt32], Int,
            UnsafePointer[UInt8], Int,
        ) -> Int
    ]("turbotoken_decode_bpe_from_ranks")
    return func(rank_bytes, rank_len, tokens, token_len, out, out_cap)


fn ffi_count_bpe(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    text: UnsafePointer[UInt8],
    text_len: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
        ) -> Int
    ]("turbotoken_count_bpe_from_ranks")
    return func(rank_bytes, rank_len, text, text_len)


fn ffi_is_within_token_limit(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    text: UnsafePointer[UInt8],
    text_len: Int,
    token_limit: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
            Int,
        ) -> Int
    ]("turbotoken_is_within_token_limit_bpe_from_ranks")
    return func(rank_bytes, rank_len, text, text_len, token_limit)


fn ffi_encode_bpe_file(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    file_path: UnsafePointer[UInt8],
    file_path_len: Int,
    out: UnsafePointer[UInt32],
    out_cap: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt32], Int,
        ) -> Int
    ]("turbotoken_encode_bpe_file_from_ranks")
    return func(rank_bytes, rank_len, file_path, file_path_len, out, out_cap)


fn ffi_count_bpe_file(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    file_path: UnsafePointer[UInt8],
    file_path_len: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
        ) -> Int
    ]("turbotoken_count_bpe_file_from_ranks")
    return func(rank_bytes, rank_len, file_path, file_path_len)


fn ffi_is_within_token_limit_file(
    rank_bytes: UnsafePointer[UInt8],
    rank_len: Int,
    file_path: UnsafePointer[UInt8],
    file_path_len: Int,
    token_limit: Int,
) -> Int:
    var h = load_library()
    var func = h.get_function[
        fn (
            UnsafePointer[UInt8], Int,
            UnsafePointer[UInt8], Int,
            Int,
        ) -> Int
    ]("turbotoken_is_within_token_limit_bpe_file_from_ranks")
    return func(rank_bytes, rank_len, file_path, file_path_len, token_limit)
