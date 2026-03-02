local M = {}

local R50K_PAT_STR = [['(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s]]

local CL100K_PAT_STR = [['(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s]]

local O200K_PAT_STR = table.concat({
    [[[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?]],
    [[[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?]],
    [[\p{N}{1,3}]],
    [[ ?[^\s\p{L}\p{N}]+[\r\n/]*]],
    [[\s*[\r\n]+]],
    [[\s+(?!\S)]],
    [[\s+]],
}, "|")

M.ENCODING_SPECS = {
    o200k_base = {
        name = "o200k_base",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str = O200K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 199999, ["<|endofprompt|>"] = 200018 },
        n_vocab = 200019,
    },
    cl100k_base = {
        name = "cl100k_base",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        pat_str = CL100K_PAT_STR,
        special_tokens = {
            ["<|endoftext|>"] = 100257,
            ["<|fim_prefix|>"] = 100258,
            ["<|fim_middle|>"] = 100259,
            ["<|fim_suffix|>"] = 100260,
            ["<|endofprompt|>"] = 100276,
        },
        n_vocab = 100277,
    },
    p50k_base = {
        name = "p50k_base",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str = R50K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 50256 },
        n_vocab = 50281,
    },
    r50k_base = {
        name = "r50k_base",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str = R50K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 50256 },
        n_vocab = 50257,
    },
    gpt2 = {
        name = "gpt2",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        pat_str = R50K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 50256 },
        n_vocab = 50257,
    },
    p50k_edit = {
        name = "p50k_edit",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        pat_str = R50K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 50256 },
        n_vocab = 50281,
    },
    o200k_harmony = {
        name = "o200k_harmony",
        rank_file_url = "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        pat_str = O200K_PAT_STR,
        special_tokens = { ["<|endoftext|>"] = 199999, ["<|endofprompt|>"] = 200018 },
        n_vocab = 200019,
    },
}

M.MODEL_TO_ENCODING = {
    ["o1"] = "o200k_base",
    ["o3"] = "o200k_base",
    ["o4-mini"] = "o200k_base",
    ["gpt-5"] = "o200k_base",
    ["gpt-4.1"] = "o200k_base",
    ["gpt-4o"] = "o200k_base",
    ["gpt-4o-mini"] = "o200k_base",
    ["gpt-4.1-mini"] = "o200k_base",
    ["gpt-4.1-nano"] = "o200k_base",
    ["gpt-oss-120b"] = "o200k_harmony",
    ["gpt-4"] = "cl100k_base",
    ["gpt-3.5-turbo"] = "cl100k_base",
    ["gpt-3.5"] = "cl100k_base",
    ["gpt-35-turbo"] = "cl100k_base",
    ["davinci-002"] = "cl100k_base",
    ["babbage-002"] = "cl100k_base",
    ["text-embedding-ada-002"] = "cl100k_base",
    ["text-embedding-3-small"] = "cl100k_base",
    ["text-embedding-3-large"] = "cl100k_base",
    ["text-davinci-003"] = "p50k_base",
    ["text-davinci-002"] = "p50k_base",
    ["text-davinci-001"] = "r50k_base",
    ["text-curie-001"] = "r50k_base",
    ["text-babbage-001"] = "r50k_base",
    ["text-ada-001"] = "r50k_base",
    ["davinci"] = "r50k_base",
    ["curie"] = "r50k_base",
    ["babbage"] = "r50k_base",
    ["ada"] = "r50k_base",
    ["code-davinci-002"] = "p50k_base",
    ["code-davinci-001"] = "p50k_base",
    ["code-cushman-002"] = "p50k_base",
    ["code-cushman-001"] = "p50k_base",
    ["davinci-codex"] = "p50k_base",
    ["cushman-codex"] = "p50k_base",
    ["text-davinci-edit-001"] = "p50k_edit",
    ["code-davinci-edit-001"] = "p50k_edit",
    ["text-similarity-davinci-001"] = "r50k_base",
    ["text-similarity-curie-001"] = "r50k_base",
    ["text-similarity-babbage-001"] = "r50k_base",
    ["text-similarity-ada-001"] = "r50k_base",
    ["text-search-davinci-doc-001"] = "r50k_base",
    ["text-search-curie-doc-001"] = "r50k_base",
    ["text-search-babbage-doc-001"] = "r50k_base",
    ["text-search-ada-doc-001"] = "r50k_base",
    ["code-search-babbage-code-001"] = "r50k_base",
    ["code-search-ada-code-001"] = "r50k_base",
    ["gpt2"] = "gpt2",
    ["gpt-2"] = "r50k_base",
}

M.MODEL_PREFIX_TO_ENCODING = {
    { prefix = "o1-", encoding = "o200k_base" },
    { prefix = "o3-", encoding = "o200k_base" },
    { prefix = "o4-mini-", encoding = "o200k_base" },
    { prefix = "gpt-5-", encoding = "o200k_base" },
    { prefix = "gpt-4.5-", encoding = "o200k_base" },
    { prefix = "gpt-4.1-", encoding = "o200k_base" },
    { prefix = "chatgpt-4o-", encoding = "o200k_base" },
    { prefix = "gpt-4o-", encoding = "o200k_base" },
    { prefix = "gpt-oss-", encoding = "o200k_harmony" },
    { prefix = "gpt-4-", encoding = "cl100k_base" },
    { prefix = "gpt-3.5-turbo-", encoding = "cl100k_base" },
    { prefix = "gpt-35-turbo-", encoding = "cl100k_base" },
    { prefix = "ft:gpt-4o", encoding = "o200k_base" },
    { prefix = "ft:gpt-4", encoding = "cl100k_base" },
    { prefix = "ft:gpt-3.5-turbo", encoding = "cl100k_base" },
    { prefix = "ft:davinci-002", encoding = "cl100k_base" },
    { prefix = "ft:babbage-002", encoding = "cl100k_base" },
}

function M.get_encoding_spec(name)
    local spec = M.ENCODING_SPECS[name]
    if not spec then
        local names = M.list_encoding_names()
        error("Unknown encoding '" .. name .. "'. Supported encodings: " .. table.concat(names, ", "))
    end
    return spec
end

function M.model_to_encoding(model)
    local enc = M.MODEL_TO_ENCODING[model]
    if enc then
        return enc
    end

    for _, entry in ipairs(M.MODEL_PREFIX_TO_ENCODING) do
        if model:sub(1, #entry.prefix) == entry.prefix then
            return entry.encoding
        end
    end

    error("Could not automatically map '" .. model .. "' to an encoding. "
        .. "Use get_encoding(name) to select one explicitly.")
end

function M.list_encoding_names()
    local names = {}
    for name, _ in pairs(M.ENCODING_SPECS) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

return M
