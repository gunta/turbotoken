/// A single chat message with role and content.
#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub role: String,
    pub name: Option<String>,
    pub content: String,
}

/// Template strings for formatting chat messages.
#[derive(Debug, Clone)]
pub struct ChatTemplate {
    /// Prefix inserted before each message (may contain `{role}`).
    pub message_prefix: String,
    /// Suffix inserted after each message.
    pub message_suffix: String,
    /// Optional prefix for the trailing assistant turn.
    pub assistant_prefix: Option<String>,
}

/// Supported chat template modes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatTemplateMode {
    TurbotokenV1,
    ImTokens,
}

/// Resolve a chat template mode to its template strings.
pub fn resolve_chat_template(mode: ChatTemplateMode) -> ChatTemplate {
    match mode {
        ChatTemplateMode::TurbotokenV1 => ChatTemplate {
            message_prefix: "[[role:{role}]]\n".to_string(),
            message_suffix: "\n[[/message]]\n".to_string(),
            assistant_prefix: Some("[[role:{role}]]\n".to_string()),
        },
        ChatTemplateMode::ImTokens => ChatTemplate {
            message_prefix: "<|im_start|>{role}\n".to_string(),
            message_suffix: "<|im_end|>\n".to_string(),
            assistant_prefix: Some("<|im_start|>{role}\n".to_string()),
        },
    }
}

/// Replace `{role}` in a template string with the actual role name.
pub fn format_chat_role(template_part: &str, role: &str) -> String {
    template_part.replace("{role}", role)
}
