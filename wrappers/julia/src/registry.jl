"""
    EncodingSpec

Specification for a BPE encoding, including rank file URL, regex pattern, and special tokens.
"""
struct EncodingSpec
    name::String
    rank_file_url::String
    pat_str::String
    special_tokens::Dict{String, Int}
    n_vocab::Int
end

const _R50K_PAT_STR = raw"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"

const _CL100K_PAT_STR = raw"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"

const _O200K_PAT_STR = join([
    raw"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    raw"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?",
    raw"\p{N}{1,3}",
    raw" ?[^\s\p{L}\p{N}]+[\r\n/]*",
    raw"\s*[\r\n]+",
    raw"\s+(?!\S)",
    raw"\s+",
], "|")

const ENCODING_SPECS = Dict{String, EncodingSpec}(
    "o200k_base" => EncodingSpec(
        "o200k_base",
        "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        _O200K_PAT_STR,
        Dict("<|endoftext|>" => 199999, "<|endofprompt|>" => 200018),
        200019,
    ),
    "cl100k_base" => EncodingSpec(
        "cl100k_base",
        "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
        _CL100K_PAT_STR,
        Dict(
            "<|endoftext|>" => 100257,
            "<|fim_prefix|>" => 100258,
            "<|fim_middle|>" => 100259,
            "<|fim_suffix|>" => 100260,
            "<|endofprompt|>" => 100276,
        ),
        100277,
    ),
    "p50k_base" => EncodingSpec(
        "p50k_base",
        "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        _R50K_PAT_STR,
        Dict("<|endoftext|>" => 50256),
        50281,
    ),
    "r50k_base" => EncodingSpec(
        "r50k_base",
        "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        _R50K_PAT_STR,
        Dict("<|endoftext|>" => 50256),
        50257,
    ),
    "gpt2" => EncodingSpec(
        "gpt2",
        "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
        _R50K_PAT_STR,
        Dict("<|endoftext|>" => 50256),
        50257,
    ),
    "p50k_edit" => EncodingSpec(
        "p50k_edit",
        "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
        _R50K_PAT_STR,
        Dict("<|endoftext|>" => 50256),
        50281,
    ),
    "o200k_harmony" => EncodingSpec(
        "o200k_harmony",
        "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
        _O200K_PAT_STR,
        Dict("<|endoftext|>" => 199999, "<|endofprompt|>" => 200018),
        200019,
    ),
)

const MODEL_TO_ENCODING = Dict{String, String}(
    "o1" => "o200k_base",
    "o3" => "o200k_base",
    "o4-mini" => "o200k_base",
    "gpt-5" => "o200k_base",
    "gpt-4.1" => "o200k_base",
    "gpt-4o" => "o200k_base",
    "gpt-4o-mini" => "o200k_base",
    "gpt-4.1-mini" => "o200k_base",
    "gpt-4.1-nano" => "o200k_base",
    "gpt-oss-120b" => "o200k_harmony",
    "gpt-4" => "cl100k_base",
    "gpt-3.5-turbo" => "cl100k_base",
    "gpt-3.5" => "cl100k_base",
    "gpt-35-turbo" => "cl100k_base",
    "davinci-002" => "cl100k_base",
    "babbage-002" => "cl100k_base",
    "text-embedding-ada-002" => "cl100k_base",
    "text-embedding-3-small" => "cl100k_base",
    "text-embedding-3-large" => "cl100k_base",
    "text-davinci-003" => "p50k_base",
    "text-davinci-002" => "p50k_base",
    "text-davinci-001" => "r50k_base",
    "text-curie-001" => "r50k_base",
    "text-babbage-001" => "r50k_base",
    "text-ada-001" => "r50k_base",
    "davinci" => "r50k_base",
    "curie" => "r50k_base",
    "babbage" => "r50k_base",
    "ada" => "r50k_base",
    "code-davinci-002" => "p50k_base",
    "code-davinci-001" => "p50k_base",
    "code-cushman-002" => "p50k_base",
    "code-cushman-001" => "p50k_base",
    "davinci-codex" => "p50k_base",
    "cushman-codex" => "p50k_base",
    "text-davinci-edit-001" => "p50k_edit",
    "code-davinci-edit-001" => "p50k_edit",
    "text-similarity-davinci-001" => "r50k_base",
    "text-similarity-curie-001" => "r50k_base",
    "text-similarity-babbage-001" => "r50k_base",
    "text-similarity-ada-001" => "r50k_base",
    "text-search-davinci-doc-001" => "r50k_base",
    "text-search-curie-doc-001" => "r50k_base",
    "text-search-babbage-doc-001" => "r50k_base",
    "text-search-ada-doc-001" => "r50k_base",
    "code-search-babbage-code-001" => "r50k_base",
    "code-search-ada-code-001" => "r50k_base",
    "gpt2" => "gpt2",
    "gpt-2" => "r50k_base",
)

const MODEL_PREFIX_TO_ENCODING = [
    ("o1-", "o200k_base"),
    ("o3-", "o200k_base"),
    ("o4-mini-", "o200k_base"),
    ("gpt-5-", "o200k_base"),
    ("gpt-4.5-", "o200k_base"),
    ("gpt-4.1-", "o200k_base"),
    ("chatgpt-4o-", "o200k_base"),
    ("gpt-4o-", "o200k_base"),
    ("gpt-oss-", "o200k_harmony"),
    ("gpt-4-", "cl100k_base"),
    ("gpt-3.5-turbo-", "cl100k_base"),
    ("gpt-35-turbo-", "cl100k_base"),
    ("ft:gpt-4o", "o200k_base"),
    ("ft:gpt-4", "cl100k_base"),
    ("ft:gpt-3.5-turbo", "cl100k_base"),
    ("ft:davinci-002", "cl100k_base"),
    ("ft:babbage-002", "cl100k_base"),
]

"""
    get_encoding_spec(name::AbstractString) -> EncodingSpec

Look up an encoding specification by name.
"""
function get_encoding_spec(name::AbstractString)::EncodingSpec
    spec = get(ENCODING_SPECS, name, nothing)
    spec === nothing && throw(UnknownEncodingError(String(name)))
    return spec
end

"""
    model_to_encoding(model::AbstractString) -> String

Map a model name to its encoding name.
"""
function model_to_encoding(model::AbstractString)::String
    # Exact match
    enc = get(MODEL_TO_ENCODING, model, nothing)
    enc !== nothing && return enc

    # Prefix match
    for (prefix, enc_name) in MODEL_PREFIX_TO_ENCODING
        startswith(model, prefix) && return enc_name
    end

    error("Could not automatically map model '$(model)' to an encoding. Use get_encoding(name) to select one explicitly.")
end

"""
    list_encoding_names() -> Vector{String}

Return a sorted list of all available encoding names.
"""
list_encoding_names()::Vector{String} = sort(collect(keys(ENCODING_SPECS)))
