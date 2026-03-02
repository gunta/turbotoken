package com.turbotoken

import groovy.transform.Canonical

/**
 * Chat message formatting for token counting and encoding.
 */
class Chat {

    /* ── ChatMessage ─────────────────────────────────────────────── */

    @Canonical
    static class ChatMessage {
        String role
        String name
        String content

        ChatMessage(String role, String content) {
            this(role, null, content)
        }

        ChatMessage(String role, String name, String content) {
            this.role = role
            this.name = name
            this.content = content ?: ''
        }
    }

    /* ── ChatTemplate ────────────────────────────────────────────── */

    @Canonical
    static class ChatTemplate {
        String messagePrefix
        String messageSuffix
        String assistantPrefix
    }

    /* ── Template modes ──────────────────────────────────────────── */

    enum TemplateMode {
        TURBOTOKEN_V1,
        IM_TOKENS
    }

    /* ── ChatOptions ─────────────────────────────────────────────── */

    @Canonical
    static class ChatOptions {
        boolean primeWithAssistantResponse = false
        TemplateMode templateMode = TemplateMode.TURBOTOKEN_V1

        ChatOptions() {}

        ChatOptions(boolean prime, TemplateMode mode) {
            this.primeWithAssistantResponse = prime
            this.templateMode = mode
        }
    }

    /* ── Resolve ─────────────────────────────────────────────────── */

    /**
     * Resolves the chat template for the given mode.
     */
    static ChatTemplate resolve(TemplateMode mode) {
        switch (mode) {
            case TemplateMode.TURBOTOKEN_V1:
                return new ChatTemplate(
                    '<|im_start|>',
                    '<|im_end|>\n',
                    '<|im_start|>assistant\n'
                )
            case TemplateMode.IM_TOKENS:
                return new ChatTemplate(
                    '<|im_start|>',
                    '<|im_end|>\n',
                    '<|im_start|>assistant\n'
                )
            default:
                throw new IllegalArgumentException("Unknown template mode: ${mode}")
        }
    }

    /**
     * Formats a list of chat messages into a single string for tokenization.
     */
    static String formatMessages(List<ChatMessage> messages, ChatOptions options = new ChatOptions()) {
        def template = resolve(options.templateMode)
        def sb = new StringBuilder()

        messages.each { msg ->
            sb.append(template.messagePrefix)
            sb.append(msg.role)
            if (msg.name != null) {
                sb.append(" name=${msg.name}")
            }
            sb.append('\n')
            sb.append(msg.content)
            sb.append(template.messageSuffix)
        }

        if (options.primeWithAssistantResponse) {
            sb.append(template.assistantPrefix)
        }

        sb.toString()
    }
}
