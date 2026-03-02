export interface ChatMessage {
  role?: string;
  name?: string;
  content?: string;
}

export interface ChatTemplate {
  messagePrefix: string;
  messageSuffix: string;
  assistantPrefix?: string | null;
}

export type ChatTemplateMode = "turbotoken_v1" | "im_tokens";

export interface ChatOptions {
  primeWithAssistantResponse?: string | null;
  template?: ChatTemplateMode | ChatTemplate;
}

function formatChatRole(templatePart: string, role: string): string {
  return templatePart.split("{role}").join(role);
}

export function resolveChatTemplate(
  template: ChatTemplateMode | ChatTemplate | undefined
): ChatTemplate {
  if (template === undefined || template === "turbotoken_v1") {
    return {
      messagePrefix: "[[role:{role}]]\n",
      messageSuffix: "\n[[/message]]\n",
      assistantPrefix: "[[role:{role}]]\n",
    };
  }
  if (template === "im_tokens") {
    return {
      messagePrefix: "<|im_start|>{role}\n",
      messageSuffix: "<|im_end|>\n",
      assistantPrefix: "<|im_start|>{role}\n",
    };
  }
  if (
    typeof template.messagePrefix !== "string" ||
    template.messagePrefix.length === 0
  ) {
    throw new Error("chat template requires non-empty messagePrefix");
  }
  if (typeof template.messageSuffix !== "string") {
    throw new Error("chat template requires string messageSuffix");
  }
  if (
    template.assistantPrefix != null &&
    typeof template.assistantPrefix !== "string"
  ) {
    throw new Error("chat template assistantPrefix must be string or null");
  }
  return {
    messagePrefix: template.messagePrefix,
    messageSuffix: template.messageSuffix,
    assistantPrefix: template.assistantPrefix ?? null,
  };
}

export function* chatSegments(
  messages: Iterable<ChatMessage>,
  options: ChatOptions = {}
): Generator<string, void, undefined> {
  const template = resolveChatTemplate(options.template);
  for (const message of messages) {
    const roleValue =
      typeof message.name === "string" && message.name.length > 0
        ? message.name
        : typeof message.role === "string" && message.role.length > 0
          ? message.role
          : "user";
    const content =
      typeof message.content === "string" ? message.content : "";

    yield formatChatRole(template.messagePrefix, roleValue);
    if (content.length > 0) {
      yield content;
    }
    yield template.messageSuffix;
  }

  const prime = options.primeWithAssistantResponse ?? "assistant";
  if (
    typeof prime === "string" &&
    prime.length > 0 &&
    template.assistantPrefix
  ) {
    yield formatChatRole(template.assistantPrefix, prime);
  }
}
