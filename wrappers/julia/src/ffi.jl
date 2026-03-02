const LIB_PATH = Ref{String}("")

function find_library()::String
    # 1. Environment variable override
    env_path = get(ENV, "TURBOTOKEN_NATIVE_LIB", "")
    if !isempty(env_path) && isfile(env_path)
        return env_path
    end

    # Platform-specific library name
    if Sys.isapple()
        libname = "libturbotoken.dylib"
    elseif Sys.iswindows()
        libname = "turbotoken.dll"
    else
        libname = "libturbotoken.so"
    end

    # 2. Common paths relative to this package
    pkg_dir = dirname(dirname(@__DIR__))
    candidates = [
        joinpath(pkg_dir, "zig-out", "lib", libname),
        joinpath(pkg_dir, "..", "zig-out", "lib", libname),
        joinpath(dirname(pkg_dir), "zig-out", "lib", libname),
        joinpath("/usr", "local", "lib", libname),
        joinpath("/usr", "lib", libname),
    ]

    for path in candidates
        if isfile(path)
            return path
        end
    end

    error("Could not find turbotoken native library. Set TURBOTOKEN_NATIVE_LIB environment variable to the library path.")
end

function _lib()::String
    if isempty(LIB_PATH[])
        LIB_PATH[] = find_library()
    end
    return LIB_PATH[]
end

"""
    ffi_version() -> String

Return the native library version string.
"""
function ffi_version()::String
    ptr = ccall((:turbotoken_version, _lib()), Cstring, ())
    return unsafe_string(ptr)
end

"""
    ffi_clear_cache()

Clear the internal rank table cache in the native library.
"""
function ffi_clear_cache()
    ccall((:turbotoken_clear_rank_table_cache, _lib()), Cvoid, ())
    return nothing
end

"""
    ffi_encode_bpe(rank_bytes::Vector{UInt8}, text::AbstractString) -> Vector{UInt32}

BPE-encode text using a preloaded rank table. Uses two-pass allocation.
"""
function ffi_encode_bpe(rank_bytes::Vector{UInt8}, text::AbstractString)::Vector{UInt32}
    text_bytes = Vector{UInt8}(codeunits(text))
    text_len = length(text_bytes)
    rank_len = length(rank_bytes)

    # Pass 1: query needed capacity
    n = ccall((:turbotoken_encode_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t),
        rank_bytes, rank_len, text_bytes, text_len, C_NULL, 0)
    n < 0 && throw(TurbotokenError("encode_bpe failed (error code $n)"))

    # Pass 2: fill buffer
    out = Vector{UInt32}(undef, n)
    n2 = ccall((:turbotoken_encode_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t),
        rank_bytes, rank_len, text_bytes, text_len, out, n)
    n2 < 0 && throw(TurbotokenError("encode_bpe pass 2 failed (error code $n2)"))

    return resize!(out, n2)
end

"""
    ffi_decode_bpe(rank_bytes::Vector{UInt8}, tokens::Vector{UInt32}) -> String

BPE-decode token IDs back to a UTF-8 string. Uses two-pass allocation.
"""
function ffi_decode_bpe(rank_bytes::Vector{UInt8}, tokens::Vector{UInt32})::String
    rank_len = length(rank_bytes)
    token_len = length(tokens)

    # Pass 1: query needed capacity
    n = ccall((:turbotoken_decode_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t, Ptr{UInt8}, Csize_t),
        rank_bytes, rank_len, tokens, token_len, C_NULL, 0)
    n < 0 && throw(TurbotokenError("decode_bpe failed (error code $n)"))

    # Pass 2: fill buffer
    out = Vector{UInt8}(undef, n)
    n2 = ccall((:turbotoken_decode_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t, Ptr{UInt8}, Csize_t),
        rank_bytes, rank_len, tokens, token_len, out, n)
    n2 < 0 && throw(TurbotokenError("decode_bpe pass 2 failed (error code $n2)"))

    return String(resize!(out, n2))
end

"""
    ffi_count_bpe(rank_bytes::Vector{UInt8}, text::AbstractString) -> Int

Count BPE tokens without materializing the token array.
"""
function ffi_count_bpe(rank_bytes::Vector{UInt8}, text::AbstractString)::Int
    text_bytes = Vector{UInt8}(codeunits(text))
    n = ccall((:turbotoken_count_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t),
        rank_bytes, length(rank_bytes), text_bytes, length(text_bytes))
    n < 0 && throw(TurbotokenError("count_bpe failed (error code $n)"))
    return Int(n)
end

"""
    ffi_is_within_token_limit(rank_bytes::Vector{UInt8}, text::AbstractString, limit::Int) -> Union{Int, Nothing}

Check if text is within a token limit. Returns token count if within limit, nothing if exceeded.
"""
function ffi_is_within_token_limit(rank_bytes::Vector{UInt8}, text::AbstractString, limit::Int)::Union{Int, Nothing}
    text_bytes = Vector{UInt8}(codeunits(text))
    n = ccall((:turbotoken_is_within_token_limit_bpe_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Csize_t),
        rank_bytes, length(rank_bytes), text_bytes, length(text_bytes), limit)
    n == -2 && return nothing
    n < 0 && throw(TurbotokenError("is_within_token_limit failed (error code $n)"))
    return Int(n)
end

"""
    ffi_encode_bpe_file(rank_bytes::Vector{UInt8}, path::AbstractString) -> Vector{UInt32}

BPE-encode a file's contents. Uses two-pass allocation.
"""
function ffi_encode_bpe_file(rank_bytes::Vector{UInt8}, path::AbstractString)::Vector{UInt32}
    path_bytes = Vector{UInt8}(codeunits(path))
    rank_len = length(rank_bytes)
    path_len = length(path_bytes)

    # Pass 1: query needed capacity
    n = ccall((:turbotoken_encode_bpe_file_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t),
        rank_bytes, rank_len, path_bytes, path_len, C_NULL, 0)
    n < 0 && throw(TurbotokenError("encode_bpe_file failed (error code $n)"))

    # Pass 2: fill buffer
    out = Vector{UInt32}(undef, n)
    n2 = ccall((:turbotoken_encode_bpe_file_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Ptr{UInt32}, Csize_t),
        rank_bytes, rank_len, path_bytes, path_len, out, n)
    n2 < 0 && throw(TurbotokenError("encode_bpe_file pass 2 failed (error code $n2)"))

    return resize!(out, n2)
end

"""
    ffi_count_bpe_file(rank_bytes::Vector{UInt8}, path::AbstractString) -> Int

Count BPE tokens in a file without materializing the token array.
"""
function ffi_count_bpe_file(rank_bytes::Vector{UInt8}, path::AbstractString)::Int
    path_bytes = Vector{UInt8}(codeunits(path))
    n = ccall((:turbotoken_count_bpe_file_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t),
        rank_bytes, length(rank_bytes), path_bytes, length(path_bytes))
    n < 0 && throw(TurbotokenError("count_bpe_file failed (error code $n)"))
    return Int(n)
end

"""
    ffi_is_within_token_limit_file(rank_bytes::Vector{UInt8}, path::AbstractString, limit::Int) -> Union{Int, Nothing}

Check if a file's content is within a token limit.
"""
function ffi_is_within_token_limit_file(rank_bytes::Vector{UInt8}, path::AbstractString, limit::Int)::Union{Int, Nothing}
    path_bytes = Vector{UInt8}(codeunits(path))
    n = ccall((:turbotoken_is_within_token_limit_bpe_file_from_ranks, _lib()), Cssize_t,
        (Ptr{UInt8}, Csize_t, Ptr{UInt8}, Csize_t, Csize_t),
        rank_bytes, length(rank_bytes), path_bytes, length(path_bytes), limit)
    n == -2 && return nothing
    n < 0 && throw(TurbotokenError("is_within_token_limit_file failed (error code $n)"))
    return Int(n)
end
