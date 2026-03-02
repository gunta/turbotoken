import Foundation

/// A chat message with role and content.
public struct ChatMessage: Sendable {
    public let role: String
    public let name: String?
    public let content: String

    public init(role: String, name: String? = nil, content: String) {
        self.role = role
        self.name = name
        self.content = content
    }
}

/// Template for formatting chat messages.
public struct ChatTemplate: Sendable {
    public let messagePrefix: String
    public let messageSuffix: String
    public let assistantPrefix: String?

    public init(
        messagePrefix: String = "",
        messageSuffix: String = "",
        assistantPrefix: String? = nil
    ) {
        self.messagePrefix = messagePrefix
        self.messageSuffix = messageSuffix
        self.assistantPrefix = assistantPrefix
    }
}

/// Chat template rendering mode.
public enum ChatTemplateMode: Sendable {
    /// TurboToken v1 template: "<|im_start|>role\ncontent<|im_end|>\n"
    case turbotokenV1
    /// OpenAI im_tokens style.
    case imTokens
}

/// Options for chat encoding.
public struct ChatOptions: Sendable {
    public let primeWithAssistantResponse: Bool
    public let template: ChatTemplate?
    public let mode: ChatTemplateMode

    public init(
        primeWithAssistantResponse: Bool = false,
        template: ChatTemplate? = nil,
        mode: ChatTemplateMode = .turbotokenV1
    ) {
        self.primeWithAssistantResponse = primeWithAssistantResponse
        self.template = template
        self.mode = mode
    }
}

/// Format a chat conversation into a single string for tokenization.
internal func formatChat(_ messages: [ChatMessage], options: ChatOptions) -> String {
    var result = ""
    let template = options.template ?? ChatTemplate()

    switch options.mode {
    case .turbotokenV1:
        for message in messages {
            result += "<|im_start|>"
            if let name = message.name {
                result += "\(message.role) name=\(name)\n"
            } else {
                result += "\(message.role)\n"
            }
            result += "\(message.content)<|im_end|>\n"
        }
        if options.primeWithAssistantResponse {
            result += "<|im_start|>assistant\n"
        }

    case .imTokens:
        for message in messages {
            result += template.messagePrefix
            if let name = message.name {
                result += "\(message.role) name=\(name)\n"
            } else {
                result += "\(message.role)\n"
            }
            result += message.content
            result += template.messageSuffix
        }
        if options.primeWithAssistantResponse, let prefix = template.assistantPrefix {
            result += prefix
        }
    }

    return result
}
