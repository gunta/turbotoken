package com.turbotoken

/** A single chat message. */
case class ChatMessage(
  role: String,
  name: Option[String] = None,
  content: String = ""
)

/** Resolved template strings for chat formatting. */
case class ChatTemplate(
  messagePrefix: String,
  messageSuffix: String,
  assistantPrefix: Option[String] = None
)

/** Chat template mode selector. */
sealed trait ChatTemplateMode

case object TurbotokenV1 extends ChatTemplateMode
case object ImTokens extends ChatTemplateMode

/** Options for chat encoding/counting. */
case class ChatOptions(
  primeWithAssistantResponse: Option[String] = Some("assistant"),
  template: ChatTemplateMode = TurbotokenV1
)

object Chat {
  /** Resolves a ChatTemplateMode to its concrete ChatTemplate. */
  def resolveChatTemplate(mode: ChatTemplateMode): ChatTemplate = mode match {
    case TurbotokenV1 =>
      ChatTemplate(
        messagePrefix = "<|im_start|>",
        messageSuffix = "<|im_end|>\n",
        assistantPrefix = Some("<|im_start|>assistant\n")
      )
    case ImTokens =>
      ChatTemplate(
        messagePrefix = "<|im_start|>",
        messageSuffix = "<|im_end|>\n",
        assistantPrefix = Some("<|im_start|>assistant\n")
      )
  }

  /** Formats chat messages into a single string for tokenization. */
  def formatMessages(messages: Seq[ChatMessage], options: ChatOptions): String = {
    val template = resolveChatTemplate(options.template)
    val sb = new StringBuilder

    messages.foreach { msg =>
      sb.append(template.messagePrefix)
      sb.append(msg.role)
      msg.name.foreach(n => sb.append(s" name=$n"))
      sb.append('\n')
      sb.append(msg.content)
      sb.append(template.messageSuffix)
    }

    if (options.primeWithAssistantResponse.isDefined) {
      template.assistantPrefix.foreach(sb.append)
    }

    sb.toString()
  }
}
