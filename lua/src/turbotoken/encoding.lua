local bridge = require("turbotoken.ffi_bridge")
local chat = require("turbotoken.chat")

local Encoding = {}
Encoding.__index = Encoding

--- Create a new Encoding instance.
-- @param name string Encoding name
-- @param rank_payload string Raw rank file bytes
-- @param spec table EncodingSpec from registry
-- @return Encoding
function Encoding.new(name, rank_payload, spec)
    local self = setmetatable({}, Encoding)
    self._name = name
    self._rank_payload = rank_payload
    self._rank_len = #rank_payload
    self._spec = spec
    return self
end

--- Get encoding name.
function Encoding:name()
    return self._name
end

--- Get vocabulary size.
function Encoding:n_vocab()
    return self._spec.n_vocab
end

--- Get end-of-text token ID.
function Encoding:eot_token()
    return self._spec.special_tokens["<|endoftext|>"]
end

--- Encode text to token IDs.
-- @param text string UTF-8 input text
-- @return table Array of token IDs
function Encoding:encode(text)
    local tokens, _ = bridge.encode_bpe_from_ranks(
        self._rank_payload, self._rank_len,
        text, #text
    )
    return tokens
end

--- Decode token IDs back to text.
-- @param tokens table Array of token IDs
-- @return string UTF-8 text
function Encoding:decode(tokens)
    return bridge.decode_bpe_from_ranks(
        self._rank_payload, self._rank_len,
        tokens, #tokens
    )
end

--- Count tokens in text without materializing the token array.
-- @param text string UTF-8 input text
-- @return number Token count
function Encoding:count(text)
    return bridge.count_bpe_from_ranks(
        self._rank_payload, self._rank_len,
        text, #text
    )
end

--- Alias for count().
function Encoding:count_tokens(text)
    return self:count(text)
end

--- Check if text is within a token limit.
-- @param text string UTF-8 input text
-- @param limit number Maximum token count
-- @return number|nil Token count if within limit, nil if exceeded
function Encoding:is_within_token_limit(text, limit)
    return bridge.is_within_token_limit_bpe_from_ranks(
        self._rank_payload, self._rank_len,
        text, #text,
        limit
    )
end

--- Encode chat messages to token IDs.
-- @param messages table[] Array of ChatMessage tables
-- @param opts table|nil Options
-- @return table Array of token IDs
function Encoding:encode_chat(messages, opts)
    return chat.encode_chat(self, messages, opts)
end

--- Count tokens for chat messages.
-- @param messages table[] Array of ChatMessage tables
-- @param opts table|nil Options
-- @return number Token count
function Encoding:count_chat(messages, opts)
    return chat.count_chat(self, messages, opts)
end

--- Check if chat messages are within a token limit.
-- @param messages table[] Array of ChatMessage tables
-- @param limit number Token limit
-- @param opts table|nil Options
-- @return number|nil Token count if within limit, nil if exceeded
function Encoding:is_chat_within_token_limit(messages, limit, opts)
    return chat.is_chat_within_token_limit(self, messages, limit, opts)
end

--- Encode a file's contents to token IDs.
-- @param file_path string Path to file
-- @return table Array of token IDs
function Encoding:encode_file_path(file_path)
    local tokens, _ = bridge.encode_bpe_file_from_ranks(
        self._rank_payload, self._rank_len,
        file_path, #file_path
    )
    return tokens
end

--- Count tokens in a file without materializing the token array.
-- @param file_path string Path to file
-- @return number Token count
function Encoding:count_file_path(file_path)
    return bridge.count_bpe_file_from_ranks(
        self._rank_payload, self._rank_len,
        file_path, #file_path
    )
end

--- Check if a file's content is within a token limit.
-- @param file_path string Path to file
-- @param limit number Maximum token count
-- @return number|nil Token count if within limit, nil if exceeded
function Encoding:is_file_path_within_token_limit(file_path, limit)
    return bridge.is_within_token_limit_bpe_file_from_ranks(
        self._rank_payload, self._rank_len,
        file_path, #file_path,
        limit
    )
end

return Encoding
