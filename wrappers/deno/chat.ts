export interface ChatMessage {
  role: string;
  name?: string;
  content: string;
}

export type ChatTemplateMode = "turbotoken_v1" | "im_tokens";

export interface ChatTemplate {
  messagePrefix: string;
  messageSuffix: string;
  assistantPrefix?: string;
}

export interface ChatOptions {
  primeWithAssistantResponse?: boolean;
  templateMode?: ChatTemplateMode;
  template?: ChatTemplate;
}

export function resolveChatTemplate(
  mode: ChatTemplateMode,
): ChatTemplate {
  switch (mode) {
    case "turbotoken_v1":
      return {
        messagePrefix: "<|im_start|>",
        messageSuffix: "<|im_end|>\n",
        assistantPrefix: "<|im_start|>assistant\n",
      };
    case "im_tokens":
      return {
        messagePrefix: "",
        messageSuffix: "",
        assistantPrefix: undefined,
      };
  }
}

export function formatChat(
  messages: ChatMessage[],
  options: ChatOptions = {},
): string {
  const mode = options.templateMode ?? "turbotoken_v1";
  const template = options.template ?? resolveChatTemplate(mode);
  const parts: string[] = [];

  switch (mode) {
    case "turbotoken_v1":
      for (const msg of messages) {
        parts.push("<|im_start|>");
        if (msg.name) {
          parts.push(`${msg.role} name=${msg.name}\n`);
        } else {
          parts.push(`${msg.role}\n`);
        }
        parts.push(`${msg.content}<|im_end|>\n`);
      }
      if (options.primeWithAssistantResponse) {
        parts.push("<|im_start|>assistant\n");
      }
      break;

    case "im_tokens":
      for (const msg of messages) {
        parts.push(template.messagePrefix);
        if (msg.name) {
          parts.push(`${msg.role} name=${msg.name}\n`);
        } else {
          parts.push(`${msg.role}\n`);
        }
        parts.push(msg.content);
        parts.push(template.messageSuffix);
      }
      if (options.primeWithAssistantResponse && template.assistantPrefix) {
        parts.push(template.assistantPrefix);
      }
      break;
  }

  return parts.join("");
}
