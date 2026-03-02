@file:JvmName("KChatTemplate")
package com.turbotoken

/**
 * Kotlin data classes for chat message formatting.
 */
data class KChatMessage(
    val role: String,
    val content: String,
    val name: String? = null
) {
    /** Convert to the Java ChatMessage for interop. */
    fun toJava(): ChatTemplate.ChatMessage =
        ChatTemplate.ChatMessage(role, name, content)
}

data class KChatTemplate(
    val messagePrefix: String,
    val messageSuffix: String,
    val assistantPrefix: String
)

/**
 * Sealed class for template mode selection.
 */
sealed class KTemplateMode {
    object TurbotokenV1 : KTemplateMode()
    object ImTokens : KTemplateMode()

    fun toJava(): ChatTemplate.TemplateMode = when (this) {
        is TurbotokenV1 -> ChatTemplate.TemplateMode.TURBOTOKEN_V1
        is ImTokens -> ChatTemplate.TemplateMode.IM_TOKENS
    }
}

data class KChatOptions(
    val primeWithAssistantResponse: Boolean = false,
    val templateMode: KTemplateMode = KTemplateMode.TurbotokenV1
) {
    fun toJava(): ChatTemplate.ChatOptions =
        ChatTemplate.ChatOptions(primeWithAssistantResponse, templateMode.toJava())
}

/**
 * Resolves the chat template for the given mode.
 */
fun resolveTemplate(mode: KTemplateMode): KChatTemplate {
    val java = ChatTemplate.resolve(mode.toJava())
    return KChatTemplate(
        messagePrefix = java.messagePrefix,
        messageSuffix = java.messageSuffix,
        assistantPrefix = java.assistantPrefix
    )
}

/**
 * Formats chat messages into a string for tokenization.
 */
fun formatMessages(messages: List<KChatMessage>, options: KChatOptions = KChatOptions()): String {
    val javaMessages = messages.map { it.toJava() }
    return ChatTemplate.formatMessages(javaMessages, options.toJava())
}
