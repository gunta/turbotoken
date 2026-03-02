#pragma once

#include <optional>
#include <string>
#include <vector>

namespace turbotoken {

struct ChatMessage {
    std::string role;
    std::optional<std::string> name;
    std::string content;
};

struct ChatTemplate {
    std::string message_prefix;
    std::string message_suffix;
    std::optional<std::string> assistant_prefix;
};

enum class ChatTemplateMode {
    turbotoken_v1,
    im_tokens,
};

struct ChatOptions {
    ChatTemplateMode mode = ChatTemplateMode::im_tokens;
};

inline ChatTemplate resolve_chat_template(ChatTemplateMode mode) {
    switch (mode) {
    case ChatTemplateMode::im_tokens:
        return {"<|im_start|>", "<|im_end|>\n", std::nullopt};
    case ChatTemplateMode::turbotoken_v1:
        return {"<|msg_start|>", "<|msg_end|>\n", "<|assistant|>"};
    }
    return {"<|im_start|>", "<|im_end|>\n", std::nullopt};
}

} // namespace turbotoken
