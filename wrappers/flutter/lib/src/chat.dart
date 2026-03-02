/// Chat message and template types for chat token counting.

class ChatMessage {
  final String role;
  final String? name;
  final String content;

  const ChatMessage({
    required this.role,
    this.name,
    required this.content,
  });
}

class ChatTemplate {
  final String messagePrefix;
  final String messageSuffix;
  final String? assistantPrefix;

  const ChatTemplate({
    required this.messagePrefix,
    required this.messageSuffix,
    this.assistantPrefix,
  });
}

enum ChatTemplateMode {
  turbotokenV1,
  imTokens,
}

class ChatOptions {
  final String? primeWithAssistantResponse;
  final dynamic template;

  const ChatOptions({
    this.primeWithAssistantResponse,
    this.template,
  });
}

ChatTemplate resolveChatTemplate(dynamic mode) {
  if (mode is ChatTemplate) return mode;

  if (mode is ChatTemplateMode) {
    switch (mode) {
      case ChatTemplateMode.turbotokenV1:
        return const ChatTemplate(
          messagePrefix: '<|role|>\n',
          messageSuffix: '\n',
          assistantPrefix: '<|assistant|>\n',
        );
      case ChatTemplateMode.imTokens:
        return const ChatTemplate(
          messagePrefix: '<|im_start|>',
          messageSuffix: '<|im_end|>\n',
          assistantPrefix: null,
        );
    }
  }

  if (mode == 'turbotoken_v1') {
    return resolveChatTemplate(ChatTemplateMode.turbotokenV1);
  }
  if (mode == 'im_tokens') {
    return resolveChatTemplate(ChatTemplateMode.imTokens);
  }

  return resolveChatTemplate(ChatTemplateMode.imTokens);
}

String formatChatRole(String templatePart, String role) {
  return templatePart.replaceAll('<|role|>', role);
}
