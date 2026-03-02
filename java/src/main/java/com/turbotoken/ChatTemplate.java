package com.turbotoken;

import java.util.List;
import java.util.Objects;

/**
 * Chat message formatting for token counting and encoding.
 */
public final class ChatTemplate {

    /* ── ChatMessage ─────────────────────────────────────────────────── */

    public static final class ChatMessage {
        private final String role;
        private final String name;
        private final String content;

        public ChatMessage(String role, String content) {
            this(role, null, content);
        }

        public ChatMessage(String role, String name, String content) {
            this.role = Objects.requireNonNull(role, "role");
            this.name = name;
            this.content = Objects.requireNonNull(content, "content");
        }

        public String getRole()    { return role; }
        public String getName()    { return name; }
        public String getContent() { return content; }
    }

    /* ── Template ────────────────────────────────────────────────────── */

    public static final class Template {
        private final String messagePrefix;
        private final String messageSuffix;
        private final String assistantPrefix;

        public Template(String messagePrefix, String messageSuffix, String assistantPrefix) {
            this.messagePrefix = messagePrefix;
            this.messageSuffix = messageSuffix;
            this.assistantPrefix = assistantPrefix;
        }

        public String getMessagePrefix()   { return messagePrefix; }
        public String getMessageSuffix()   { return messageSuffix; }
        public String getAssistantPrefix() { return assistantPrefix; }
    }

    /* ── ChatOptions ─────────────────────────────────────────────────── */

    public static final class ChatOptions {
        private final boolean primeWithAssistantResponse;
        private final TemplateMode templateMode;

        public ChatOptions() {
            this(false, TemplateMode.TURBOTOKEN_V1);
        }

        public ChatOptions(boolean primeWithAssistantResponse, TemplateMode templateMode) {
            this.primeWithAssistantResponse = primeWithAssistantResponse;
            this.templateMode = templateMode;
        }

        public boolean isPrimeWithAssistantResponse() { return primeWithAssistantResponse; }
        public TemplateMode getTemplateMode()          { return templateMode; }
    }

    public enum TemplateMode {
        TURBOTOKEN_V1,
        IM_TOKENS
    }

    /* ── Resolve ─────────────────────────────────────────────────────── */

    /**
     * Resolves the chat template for the given mode.
     */
    public static Template resolve(TemplateMode mode) {
        switch (mode) {
            case TURBOTOKEN_V1:
                return new Template(
                    "<|im_start|>",
                    "<|im_end|>\n",
                    "<|im_start|>assistant\n"
                );
            case IM_TOKENS:
                return new Template(
                    "<|im_start|>",
                    "<|im_end|>\n",
                    "<|im_start|>assistant\n"
                );
            default:
                throw new IllegalArgumentException("Unknown template mode: " + mode);
        }
    }

    /**
     * Formats a list of chat messages into a single string for tokenization.
     */
    public static String formatMessages(List<ChatMessage> messages, ChatOptions options) {
        Template template = resolve(options.getTemplateMode());
        StringBuilder sb = new StringBuilder();

        for (ChatMessage msg : messages) {
            sb.append(template.getMessagePrefix());
            sb.append(msg.getRole());
            if (msg.getName() != null) {
                sb.append(" name=").append(msg.getName());
            }
            sb.append('\n');
            sb.append(msg.getContent());
            sb.append(template.getMessageSuffix());
        }

        if (options.isPrimeWithAssistantResponse()) {
            sb.append(template.getAssistantPrefix());
        }

        return sb.toString();
    }

    private ChatTemplate() {}
}
