"""
    Encoding

A loaded BPE encoding ready for tokenization operations.
"""
struct Encoding
    name::String
    spec::EncodingSpec
    rank_payload::Vector{UInt8}
end

"""
    encode(enc::Encoding, text::AbstractString) -> Vector{UInt32}

Encode text into BPE token IDs.
"""
encode(enc::Encoding, text::AbstractString)::Vector{UInt32} =
    ffi_encode_bpe(enc.rank_payload, text)

"""
    decode(enc::Encoding, tokens::Vector{UInt32}) -> String

Decode BPE token IDs back into a UTF-8 string.
"""
decode(enc::Encoding, tokens::Vector{UInt32})::String =
    ffi_decode_bpe(enc.rank_payload, tokens)

"""
    count(enc::Encoding, text::AbstractString) -> Int

Count the number of BPE tokens in text without materializing the token array.
"""
count(enc::Encoding, text::AbstractString)::Int =
    ffi_count_bpe(enc.rank_payload, text)

"""
    count_tokens(enc::Encoding, text::AbstractString) -> Int

Alias for `count`.
"""
const count_tokens = count

"""
    is_within_token_limit(enc::Encoding, text::AbstractString, limit::Int) -> Union{Int, Nothing}

Check if text is within a token limit.
Returns the token count if within limit, `nothing` if exceeded.
"""
is_within_token_limit(enc::Encoding, text::AbstractString, limit::Int)::Union{Int, Nothing} =
    ffi_is_within_token_limit(enc.rank_payload, text, limit)

"""
    encode_chat(enc::Encoding, messages::Vector{ChatMessage}; kwargs...) -> Vector{UInt32}

Encode chat messages into BPE token IDs.
"""
function encode_chat(enc::Encoding, messages::Vector{ChatMessage}; kwargs...)::Vector{UInt32}
    opts = ChatOptions(; kwargs...)
    text = format_chat_messages(messages; opts=opts)
    return encode(enc, text)
end

"""
    count_chat(enc::Encoding, messages::Vector{ChatMessage}; kwargs...) -> Int

Count BPE tokens for chat messages.
"""
function count_chat(enc::Encoding, messages::Vector{ChatMessage}; kwargs...)::Int
    opts = ChatOptions(; kwargs...)
    text = format_chat_messages(messages; opts=opts)
    return count(enc, text)
end

"""
    is_chat_within_token_limit(enc::Encoding, messages::Vector{ChatMessage}, limit::Int; kwargs...) -> Union{Int, Nothing}

Check if chat messages are within a token limit.
"""
function is_chat_within_token_limit(enc::Encoding, messages::Vector{ChatMessage}, limit::Int; kwargs...)::Union{Int, Nothing}
    opts = ChatOptions(; kwargs...)
    text = format_chat_messages(messages; opts=opts)
    return is_within_token_limit(enc, text, limit)
end

"""
    encode_file_path(enc::Encoding, path::AbstractString) -> Vector{UInt32}

Encode a file's contents into BPE token IDs.
"""
encode_file_path(enc::Encoding, path::AbstractString)::Vector{UInt32} =
    ffi_encode_bpe_file(enc.rank_payload, path)

"""
    count_file_path(enc::Encoding, path::AbstractString) -> Int

Count BPE tokens in a file.
"""
count_file_path(enc::Encoding, path::AbstractString)::Int =
    ffi_count_bpe_file(enc.rank_payload, path)

"""
    is_file_path_within_token_limit(enc::Encoding, path::AbstractString, limit::Int) -> Union{Int, Nothing}

Check if a file's content is within a token limit.
"""
is_file_path_within_token_limit(enc::Encoding, path::AbstractString, limit::Int)::Union{Int, Nothing} =
    ffi_is_within_token_limit_file(enc.rank_payload, path, limit)

function Base.show(io::IO, enc::Encoding)
    print(io, "Encoding(\"$(enc.name)\", n_vocab=$(enc.spec.n_vocab))")
end
