from collections import Optional


@value
struct ChatMessage(Stringable):
    var role: String
    var name: Optional[String]
    var content: String

    fn __init__(out self, role: String, content: String, name: Optional[String] = None):
        self.role = role
        self.content = content
        self.name = name

    fn __str__(self) -> String:
        return "ChatMessage(role=" + self.role + ")"


@value
struct ChatTemplate:
    var message_prefix: String
    var message_suffix: String
    var assistant_prefix: Optional[String]

    fn __init__(
        out self,
        message_prefix: String = "",
        message_suffix: String = "",
        assistant_prefix: Optional[String] = None,
    ):
        self.message_prefix = message_prefix
        self.message_suffix = message_suffix
        self.assistant_prefix = assistant_prefix


@value
struct ChatOptions:
    var prime_with_assistant_response: Bool
    var template_mode: String  # "turbotoken_v1" or "im_tokens"

    fn __init__(
        out self,
        prime_with_assistant_response: Bool = False,
        template_mode: String = "turbotoken_v1",
    ):
        self.prime_with_assistant_response = prime_with_assistant_response
        self.template_mode = template_mode


fn resolve_chat_template(mode: String) -> ChatTemplate:
    if mode == "turbotoken_v1":
        return ChatTemplate(
            message_prefix="<|im_start|>",
            message_suffix="<|im_end|>\n",
            assistant_prefix=String("<|im_start|>assistant\n"),
        )
    else:
        return ChatTemplate(
            message_prefix="",
            message_suffix="",
            assistant_prefix=None,
        )


fn format_chat(messages: List[ChatMessage], options: ChatOptions = ChatOptions()) -> String:
    var result = String("")
    var template = resolve_chat_template(options.template_mode)

    if options.template_mode == "turbotoken_v1":
        for i in range(len(messages)):
            var msg = messages[i]
            result += "<|im_start|>"
            if msg.name:
                result += msg.role + " name=" + msg.name.value() + "\n"
            else:
                result += msg.role + "\n"
            result += msg.content + "<|im_end|>\n"
        if options.prime_with_assistant_response:
            result += "<|im_start|>assistant\n"
    else:
        for i in range(len(messages)):
            var msg = messages[i]
            result += template.message_prefix
            if msg.name:
                result += msg.role + " name=" + msg.name.value() + "\n"
            else:
                result += msg.role + "\n"
            result += msg.content
            result += template.message_suffix
        if options.prime_with_assistant_response and template.assistant_prefix:
            result += template.assistant_prefix.value()

    return result
