local M = {}

--- Create a new chat message.
-- @param role string The message role (e.g. "system", "user", "assistant")
-- @param content string The message content
-- @param name string|nil Optional sender name
-- @return table ChatMessage
function M.new_message(role, content, name)
    return {
        role = role,
        content = content,
        name = name,
    }
end

--- Chat template with message formatting rules.
-- @param message_prefix string
-- @param message_suffix string
-- @param assistant_prefix string
-- @return table ChatTemplate
function M.new_template(message_prefix, message_suffix, assistant_prefix)
    return {
        message_prefix = message_prefix,
        message_suffix = message_suffix,
        assistant_prefix = assistant_prefix,
    }
end

--- Resolve the turbotoken_v1 chat template.
function M.resolve_turbotoken_v1()
    return M.new_template("", "\n", "<|im_start|>assistant\n")
end

--- Resolve the im_tokens chat template.
function M.resolve_im_tokens()
    return M.new_template("", "\n", "<|im_start|>assistant\n")
end

--- Format a list of chat messages using a template.
-- @param template table ChatTemplate
-- @param messages table[] Array of ChatMessage tables
-- @return string Formatted text
function M.format_messages(template, messages)
    local parts = {}
    for _, msg in ipairs(messages) do
        local name_tag = ""
        if msg.name then
            name_tag = " name=" .. msg.name
        end
        parts[#parts + 1] = template.message_prefix
            .. "<|im_start|>" .. msg.role .. name_tag .. "\n"
            .. msg.content
            .. "<|im_end|>"
            .. template.message_suffix
    end
    parts[#parts + 1] = template.assistant_prefix
    return table.concat(parts)
end

--- Encode chat messages using an encoding.
-- @param encoding table Encoding instance
-- @param messages table[] Array of ChatMessage tables
-- @param opts table|nil Options
-- @return table Array of token IDs
function M.encode_chat(encoding, messages, opts)
    local template = M.resolve_turbotoken_v1()
    local text = M.format_messages(template, messages)
    return encoding:encode(text)
end

--- Count tokens for chat messages.
-- @param encoding table Encoding instance
-- @param messages table[] Array of ChatMessage tables
-- @param opts table|nil Options
-- @return number Token count
function M.count_chat(encoding, messages, opts)
    local template = M.resolve_turbotoken_v1()
    local text = M.format_messages(template, messages)
    return encoding:count(text)
end

--- Check if chat messages are within a token limit.
-- @param encoding table Encoding instance
-- @param messages table[] Array of ChatMessage tables
-- @param limit number Token limit
-- @param opts table|nil Options
-- @return number|nil Token count, or nil if exceeded
function M.is_chat_within_token_limit(encoding, messages, limit, opts)
    local template = M.resolve_turbotoken_v1()
    local text = M.format_messages(template, messages)
    return encoding:is_within_token_limit(text, limit)
end

return M
