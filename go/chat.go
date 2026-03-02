package turbotoken

import "strings"

// ChatMessage represents a single message in a chat conversation.
type ChatMessage struct {
	Role    string
	Name    string
	Content string
}

// ChatTemplate defines the formatting template for chat messages.
type ChatTemplate struct {
	MessagePrefix   string
	MessageSuffix   string
	AssistantPrefix string
}

// ChatTemplateMode selects a built-in chat template.
type ChatTemplateMode string

const (
	// TurbotokenV1 uses turbotoken's native chat format.
	TurbotokenV1 ChatTemplateMode = "turbotoken_v1"
	// ImTokens uses the im_start/im_end token format.
	ImTokens ChatTemplateMode = "im_tokens"
)

const (
	chatStart = "<|im_start|>"
	chatEnd   = "<|im_end|>"
)

// ChatOptions configures chat encoding behavior.
type ChatOptions struct {
	// PrimeWithAssistantResponse appends an assistant prefix with this role
	// after all messages. Defaults to "assistant" if empty.
	PrimeWithAssistantResponse string

	// TemplateMode selects a built-in template. Ignored if Template is non-nil.
	TemplateMode ChatTemplateMode

	// Template provides a custom chat template. Overrides TemplateMode.
	Template *ChatTemplate
}

// ResolveChatTemplate returns the ChatTemplate for the given mode.
func ResolveChatTemplate(mode ChatTemplateMode) ChatTemplate {
	switch mode {
	case ImTokens:
		return ChatTemplate{
			MessagePrefix:   chatStart + "{role}\n",
			MessageSuffix:   chatEnd + "\n",
			AssistantPrefix: chatStart + "{role}\n",
		}
	default: // TurbotokenV1 or unset
		return ChatTemplate{
			MessagePrefix:   "[[role:{role}]]\n",
			MessageSuffix:   "\n[[/message]]\n",
			AssistantPrefix: "[[role:{role}]]\n",
		}
	}
}

// formatChatRole replaces the {role} placeholder in a template part.
func formatChatRole(templatePart, role string) string {
	return strings.ReplaceAll(templatePart, "{role}", role)
}

// resolveTemplate returns the effective ChatTemplate from ChatOptions.
func resolveTemplate(opts *ChatOptions) ChatTemplate {
	if opts != nil && opts.Template != nil {
		return *opts.Template
	}
	mode := TurbotokenV1
	if opts != nil && opts.TemplateMode != "" {
		mode = opts.TemplateMode
	}
	return ResolveChatTemplate(mode)
}

// formatChat formats chat messages into a single string using the given template.
func formatChat(messages []ChatMessage, opts *ChatOptions) string {
	tmpl := resolveTemplate(opts)

	var b strings.Builder
	for _, msg := range messages {
		role := msg.Name
		if role == "" {
			role = msg.Role
		}
		if role == "" {
			role = "user"
		}

		b.WriteString(formatChatRole(tmpl.MessagePrefix, role))
		b.WriteString(msg.Content)
		b.WriteString(tmpl.MessageSuffix)
	}

	prime := "assistant"
	if opts != nil && opts.PrimeWithAssistantResponse != "" {
		prime = opts.PrimeWithAssistantResponse
	}
	if tmpl.AssistantPrefix != "" {
		b.WriteString(formatChatRole(tmpl.AssistantPrefix, prime))
	}

	return b.String()
}
