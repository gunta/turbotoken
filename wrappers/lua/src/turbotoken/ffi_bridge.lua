local ffi = require("ffi")

ffi.cdef[[
const char *turbotoken_version(void);
void turbotoken_clear_rank_table_cache(void);

ptrdiff_t turbotoken_count(const uint8_t *text, size_t text_len);

ptrdiff_t turbotoken_encode_utf8_bytes(
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_decode_utf8_bytes(
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

ptrdiff_t turbotoken_encode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_decode_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint32_t *tokens, size_t token_len,
    uint8_t *out_bytes, size_t out_cap);

ptrdiff_t turbotoken_count_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len);

ptrdiff_t turbotoken_is_within_token_limit_bpe_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *text, size_t text_len,
    size_t token_limit);

ptrdiff_t turbotoken_encode_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    uint32_t *out_tokens, size_t out_cap);

ptrdiff_t turbotoken_count_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len);

ptrdiff_t turbotoken_is_within_token_limit_bpe_file_from_ranks(
    const uint8_t *rank_bytes, size_t rank_len,
    const uint8_t *file_path, size_t file_path_len,
    size_t token_limit);
]]

local M = {}

local lib = nil

local function find_library()
    -- 1. Environment variable
    local env = os.getenv("TURBOTOKEN_NATIVE_LIB")
    if env and env ~= "" then
        return ffi.load(env)
    end

    -- 2. Try system library name
    local ok, l = pcall(ffi.load, "turbotoken")
    if ok then
        return l
    end

    -- 3. Try zig-out/lib/ relative paths
    local suffixes
    if ffi.os == "OSX" then
        suffixes = { "libturbotoken.dylib", "libturbotoken.so" }
    elseif ffi.os == "Windows" then
        suffixes = { "turbotoken.dll" }
    else
        suffixes = { "libturbotoken.so" }
    end

    -- Try relative to this file's typical install location
    local paths_to_try = {
        "../../../zig-out/lib/",
        "../../../../zig-out/lib/",
        "../../zig-out/lib/",
        "../zig-out/lib/",
        "./zig-out/lib/",
        "./lib/",
    }

    for _, base in ipairs(paths_to_try) do
        for _, suffix in ipairs(suffixes) do
            local ok2, l2 = pcall(ffi.load, base .. suffix)
            if ok2 then
                return l2
            end
        end
    end

    error("turbotoken: could not find native library. Set TURBOTOKEN_NATIVE_LIB environment variable.")
end

local function get_lib()
    if lib == nil then
        lib = find_library()
    end
    return lib
end

function M.version()
    return ffi.string(get_lib().turbotoken_version())
end

function M.clear_rank_table_cache()
    get_lib().turbotoken_clear_rank_table_cache()
end

function M.encode_bpe_from_ranks(rank_bytes, rank_len, text, text_len)
    local l = get_lib()

    -- Pass 1: query size
    local n = l.turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        text, text_len,
        nil, 0
    )
    if n < 0 then
        error("turbotoken_encode_bpe_from_ranks failed (pass 1): code " .. tostring(n))
    end
    if n == 0 then
        return {}, 0
    end

    -- Pass 2: fill buffer
    local buf = ffi.new("uint32_t[?]", n)
    local written = l.turbotoken_encode_bpe_from_ranks(
        rank_bytes, rank_len,
        text, text_len,
        buf, n
    )
    if written < 0 then
        error("turbotoken_encode_bpe_from_ranks failed (pass 2): code " .. tostring(written))
    end

    local tokens = {}
    for i = 0, tonumber(written) - 1 do
        tokens[i + 1] = tonumber(buf[i])
    end
    return tokens, tonumber(written)
end

function M.decode_bpe_from_ranks(rank_bytes, rank_len, tokens, token_len)
    local l = get_lib()

    if token_len == 0 then
        return ""
    end

    local token_buf = ffi.new("uint32_t[?]", token_len)
    for i = 1, token_len do
        token_buf[i - 1] = tokens[i]
    end

    -- Pass 1: query size
    local n = l.turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        token_buf, token_len,
        nil, 0
    )
    if n < 0 then
        error("turbotoken_decode_bpe_from_ranks failed (pass 1): code " .. tostring(n))
    end
    if n == 0 then
        return ""
    end

    -- Pass 2: fill buffer
    local out_buf = ffi.new("uint8_t[?]", n)
    local written = l.turbotoken_decode_bpe_from_ranks(
        rank_bytes, rank_len,
        token_buf, token_len,
        out_buf, n
    )
    if written < 0 then
        error("turbotoken_decode_bpe_from_ranks failed (pass 2): code " .. tostring(written))
    end

    return ffi.string(out_buf, written)
end

function M.count_bpe_from_ranks(rank_bytes, rank_len, text, text_len)
    local n = get_lib().turbotoken_count_bpe_from_ranks(
        rank_bytes, rank_len,
        text, text_len
    )
    if n < 0 then
        error("turbotoken_count_bpe_from_ranks failed: code " .. tostring(n))
    end
    return tonumber(n)
end

function M.is_within_token_limit_bpe_from_ranks(rank_bytes, rank_len, text, text_len, token_limit)
    local result = get_lib().turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_bytes, rank_len,
        text, text_len,
        token_limit
    )
    local r = tonumber(result)
    if r == -1 then
        error("turbotoken_is_within_token_limit_bpe_from_ranks failed")
    end
    if r == -2 then
        return nil -- limit exceeded
    end
    return r
end

function M.encode_bpe_file_from_ranks(rank_bytes, rank_len, file_path, file_path_len)
    local l = get_lib()

    -- Pass 1: query size
    local n = l.turbotoken_encode_bpe_file_from_ranks(
        rank_bytes, rank_len,
        file_path, file_path_len,
        nil, 0
    )
    if n < 0 then
        error("turbotoken_encode_bpe_file_from_ranks failed (pass 1): code " .. tostring(n))
    end
    if n == 0 then
        return {}, 0
    end

    -- Pass 2: fill buffer
    local buf = ffi.new("uint32_t[?]", n)
    local written = l.turbotoken_encode_bpe_file_from_ranks(
        rank_bytes, rank_len,
        file_path, file_path_len,
        buf, n
    )
    if written < 0 then
        error("turbotoken_encode_bpe_file_from_ranks failed (pass 2): code " .. tostring(written))
    end

    local tokens = {}
    for i = 0, tonumber(written) - 1 do
        tokens[i + 1] = tonumber(buf[i])
    end
    return tokens, tonumber(written)
end

function M.count_bpe_file_from_ranks(rank_bytes, rank_len, file_path, file_path_len)
    local n = get_lib().turbotoken_count_bpe_file_from_ranks(
        rank_bytes, rank_len,
        file_path, file_path_len
    )
    if n < 0 then
        error("turbotoken_count_bpe_file_from_ranks failed: code " .. tostring(n))
    end
    return tonumber(n)
end

function M.is_within_token_limit_bpe_file_from_ranks(rank_bytes, rank_len, file_path, file_path_len, token_limit)
    local result = get_lib().turbotoken_is_within_token_limit_bpe_file_from_ranks(
        rank_bytes, rank_len,
        file_path, file_path_len,
        token_limit
    )
    local r = tonumber(result)
    if r == -1 then
        error("turbotoken_is_within_token_limit_bpe_file_from_ranks failed")
    end
    if r == -2 then
        return nil -- limit exceeded
    end
    return r
end

return M
