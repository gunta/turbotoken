module TurboToken

include("error.jl")
include("ffi.jl")
include("registry.jl")
include("rank_cache.jl")
include("chat.jl")
include("encoding.jl")

export get_encoding, get_encoding_for_model, list_encoding_names, version
export Encoding, encode, decode, count, count_tokens, is_within_token_limit
export encode_chat, count_chat, is_chat_within_token_limit
export encode_file_path, count_file_path, is_file_path_within_token_limit

"""
    version()

Return the turbotoken native library version string.
"""
version() = ffi_version()

"""
    get_encoding(name::AbstractString) -> Encoding

Get a BPE encoding by name (e.g. "cl100k_base", "o200k_base").
"""
function get_encoding(name::AbstractString)
    spec = get_encoding_spec(String(name))
    rank_payload = read_rank_file(spec.name)
    return Encoding(spec.name, spec, rank_payload)
end

"""
    get_encoding_for_model(model::AbstractString) -> Encoding

Get the appropriate BPE encoding for a given model name.
"""
function get_encoding_for_model(model::AbstractString)
    enc_name = model_to_encoding(String(model))
    return get_encoding(enc_name)
end

end # module
