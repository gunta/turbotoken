local registry = require("turbotoken.registry")
local rank_cache = require("turbotoken.rank_cache")
local Encoding = require("turbotoken.encoding")
local bridge = require("turbotoken.ffi_bridge")

local M = {}

local encoding_cache = {}

--- Get an encoding by name.
-- @param name string Encoding name (e.g. "cl100k_base", "o200k_base")
-- @return Encoding
function M.get_encoding(name)
    if encoding_cache[name] then
        return encoding_cache[name]
    end

    local spec = registry.get_encoding_spec(name)
    local rank_payload = rank_cache.read_rank_file(name)
    local enc = Encoding.new(name, rank_payload, spec)
    encoding_cache[name] = enc
    return enc
end

--- Get encoding for a specific model.
-- @param model string Model name (e.g. "gpt-4o", "gpt-4")
-- @return Encoding
function M.get_encoding_for_model(model)
    local name = registry.model_to_encoding(model)
    return M.get_encoding(name)
end

--- List all supported encoding names.
-- @return table Array of encoding name strings
function M.list_encoding_names()
    return registry.list_encoding_names()
end

--- Get the native library version string.
-- @return string
function M.version()
    return bridge.version()
end

return M
