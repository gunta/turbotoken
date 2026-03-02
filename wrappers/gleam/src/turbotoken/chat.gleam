/// Chat message encoding support for TurboToken.
import gleam/list
import turbotoken/encoding.{type Encoding}

/// A chat message with role and content.
pub type ChatMessage {
  ChatMessage(role: String, content: String, name: String)
}

/// Chat template configuration.
pub type ChatTemplate {
  ChatTemplate(
    tokens_per_message: Int,
    tokens_per_name: Int,
    bos_token_ids: List(Int),
    eos_token_ids: List(Int),
  )
}

/// Template mode variants.
pub type TemplateMode {
  TurbotokenV1
  ImTokens
}

/// Resolve a chat template by mode.
pub fn resolve_chat_template(mode: TemplateMode, eot_token: Int) -> ChatTemplate {
  case mode {
    TurbotokenV1 ->
      ChatTemplate(
        tokens_per_message: 3,
        tokens_per_name: 1,
        bos_token_ids: [],
        eos_token_ids: [eot_token],
      )
    ImTokens ->
      ChatTemplate(
        tokens_per_message: 4,
        tokens_per_name: -1,
        bos_token_ids: [],
        eos_token_ids: [eot_token],
      )
  }
}

/// Encode chat messages into token IDs.
pub fn encode_chat(
  enc: Encoding,
  messages: List(ChatMessage),
  mode: TemplateMode,
  eot_token: Int,
) -> Result(List(Int), String) {
  let template = resolve_chat_template(mode, eot_token)

  case encode_messages(enc, messages, template, []) {
    Ok(tokens) -> Ok(list.append(tokens, template.eos_token_ids))
    Error(e) -> Error(e)
  }
}

/// Count tokens in chat messages.
pub fn count_chat(
  enc: Encoding,
  messages: List(ChatMessage),
  mode: TemplateMode,
  eot_token: Int,
) -> Result(Int, String) {
  case encode_chat(enc, messages, mode, eot_token) {
    Ok(tokens) -> Ok(list.length(tokens))
    Error(e) -> Error(e)
  }
}

fn encode_messages(
  enc: Encoding,
  messages: List(ChatMessage),
  template: ChatTemplate,
  acc: List(Int),
) -> Result(List(Int), String) {
  case messages {
    [] -> Ok(acc)
    [msg, ..rest] ->
      case encoding.encode(enc, msg.role) {
        Ok(role_tokens) ->
          case encoding.encode(enc, msg.content) {
            Ok(content_tokens) -> {
              let padding = list.repeat(0, template.tokens_per_message)
              let msg_tokens =
                list.concat([
                  template.bos_token_ids,
                  role_tokens,
                  content_tokens,
                  padding,
                ])
              encode_messages(enc, rest, template, list.append(acc, msg_tokens))
            }
            Error(e) -> Error(e)
          }
        Error(e) -> Error(e)
      }
  }
}
