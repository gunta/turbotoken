"""
    ChatMessage

A single message in a chat conversation.
"""
struct ChatMessage
    role::String
    name::Union{String, Nothing}
    content::String
end

ChatMessage(role::String, content::String) = ChatMessage(role, nothing, content)

"""
    ChatTemplate

Template for formatting chat messages into token sequences.
"""
struct ChatTemplate
    message_prefix::String
    message_suffix::String
    assistant_prefix::Union{String, Nothing}
end

"""
    ChatTemplateMode

Enum for chat template modes.
"""
@enum ChatTemplateMode begin
    turbotoken_v1
    im_tokens
end

"""
    ChatOptions

Options for chat encoding.
"""
struct ChatOptions
    mode::ChatTemplateMode
    add_assistant_prefix::Bool
end

ChatOptions(; mode::ChatTemplateMode=turbotoken_v1, add_assistant_prefix::Bool=true) =
    ChatOptions(mode, add_assistant_prefix)

"""
    resolve_chat_template(mode::ChatTemplateMode) -> ChatTemplate

Get the chat template for a given mode.
"""
function resolve_chat_template(mode::ChatTemplateMode)::ChatTemplate
    if mode == turbotoken_v1
        return ChatTemplate(
            "<|im_start|>",
            "<|im_end|>\n",
            "<|im_start|>assistant\n",
        )
    elseif mode == im_tokens
        return ChatTemplate(
            "<|im_start|>",
            "<|im_end|>\n",
            "<|im_start|>assistant\n",
        )
    else
        error("Unknown chat template mode: $mode")
    end
end

"""
    format_chat_role(template_part::String, role::String) -> String

Format a chat template part with a role name.
"""
function format_chat_role(template_part::String, role::String)::String
    return template_part * role * "\n"
end

"""
    format_chat_messages(messages::Vector{ChatMessage}; opts::ChatOptions=ChatOptions()) -> String

Format chat messages into a single string for tokenization.
"""
function format_chat_messages(messages::Vector{ChatMessage}; opts::ChatOptions=ChatOptions())::String
    template = resolve_chat_template(opts.mode)
    parts = String[]

    for msg in messages
        push!(parts, format_chat_role(template.message_prefix, msg.role))
        if msg.name !== nothing
            push!(parts, "name=" * msg.name * "\n")
        end
        push!(parts, msg.content)
        push!(parts, template.message_suffix)
    end

    if opts.add_assistant_prefix && template.assistant_prefix !== nothing
        push!(parts, template.assistant_prefix)
    end

    return join(parts)
end
