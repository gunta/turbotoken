using System.Collections.Generic;
using System.Text;

namespace TurboToken
{
    /// <summary>
    /// A chat message with role and content.
    /// </summary>
    public sealed class ChatMessage
    {
        public string Role { get; }
        public string? Name { get; }
        public string Content { get; }

        public ChatMessage(string role, string content, string? name = null)
        {
            Role = role;
            Content = content;
            Name = name;
        }
    }

    /// <summary>
    /// Template for formatting chat messages.
    /// </summary>
    public sealed class ChatTemplate
    {
        public string MessagePrefix { get; }
        public string MessageSuffix { get; }
        public string? AssistantPrefix { get; }

        public ChatTemplate(
            string messagePrefix = "",
            string messageSuffix = "",
            string? assistantPrefix = null)
        {
            MessagePrefix = messagePrefix;
            MessageSuffix = messageSuffix;
            AssistantPrefix = assistantPrefix;
        }
    }

    /// <summary>
    /// Chat template rendering mode.
    /// </summary>
    public enum ChatTemplateMode
    {
        TurbotokenV1,
        ImTokens,
    }

    /// <summary>
    /// Options for chat encoding.
    /// </summary>
    public sealed class ChatOptions
    {
        public bool PrimeWithAssistantResponse { get; }
        public ChatTemplate? Template { get; }
        public ChatTemplateMode Mode { get; }

        public ChatOptions(
            bool primeWithAssistantResponse = false,
            ChatTemplate? template = null,
            ChatTemplateMode mode = ChatTemplateMode.TurbotokenV1)
        {
            PrimeWithAssistantResponse = primeWithAssistantResponse;
            Template = template;
            Mode = mode;
        }
    }

    internal static class ChatFormatter
    {
        internal static string FormatChat(IReadOnlyList<ChatMessage> messages, ChatOptions options)
        {
            var sb = new StringBuilder();
            var template = options.Template ?? new ChatTemplate();

            switch (options.Mode)
            {
                case ChatTemplateMode.TurbotokenV1:
                    foreach (var msg in messages)
                    {
                        sb.Append("<|im_start|>");
                        if (msg.Name != null)
                            sb.Append($"{msg.Role} name={msg.Name}\n");
                        else
                            sb.Append($"{msg.Role}\n");
                        sb.Append($"{msg.Content}<|im_end|>\n");
                    }
                    if (options.PrimeWithAssistantResponse)
                        sb.Append("<|im_start|>assistant\n");
                    break;

                case ChatTemplateMode.ImTokens:
                    foreach (var msg in messages)
                    {
                        sb.Append(template.MessagePrefix);
                        if (msg.Name != null)
                            sb.Append($"{msg.Role} name={msg.Name}\n");
                        else
                            sb.Append($"{msg.Role}\n");
                        sb.Append(msg.Content);
                        sb.Append(template.MessageSuffix);
                    }
                    if (options.PrimeWithAssistantResponse && template.AssistantPrefix != null)
                        sb.Append(template.AssistantPrefix);
                    break;
            }

            return sb.ToString();
        }
    }
}
