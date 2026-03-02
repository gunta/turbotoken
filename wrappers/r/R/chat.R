#' Create a chat message
#'
#' @param role Character string, message role (e.g. "user", "assistant", "system").
#' @param content Character string, message content.
#' @param name Optional character string, name of the speaker.
#' @return A list with class "turbotoken_chat_message".
#' @export
chat_message <- function(role, content, name = NULL) {
  msg <- list(role = role, content = content, name = name)
  class(msg) <- "turbotoken_chat_message"
  msg
}

#' Create a chat template
#'
#' @param message_prefix Character string.
#' @param message_suffix Character string.
#' @param assistant_prefix Optional character string.
#' @return A list with class "turbotoken_chat_template".
#' @keywords internal
chat_template <- function(message_prefix, message_suffix, assistant_prefix = NULL) {
  list(
    message_prefix = message_prefix,
    message_suffix = message_suffix,
    assistant_prefix = assistant_prefix
  )
}

#' Resolve a chat template by mode
#'
#' @param mode Character string, "turbotoken_v1" or "im_tokens".
#' @return A chat_template list.
#' @keywords internal
resolve_chat_template <- function(mode = "turbotoken_v1") {
  if (mode %in% c("turbotoken_v1", "im_tokens")) {
    return(chat_template(
      message_prefix = "<|im_start|>",
      message_suffix = "<|im_end|>\n",
      assistant_prefix = "<|im_start|>assistant\n"
    ))
  }
  stop(sprintf("Unknown chat template mode: '%s'", mode), call. = FALSE)
}

#' Format a chat template part with a role
#'
#' @param template_part Character string, the template prefix.
#' @param role Character string, the role name.
#' @return Character string.
#' @keywords internal
format_chat_role <- function(template_part, role) {
  paste0(template_part, role, "\n")
}

#' Format chat messages into a single string
#'
#' @param messages A list of chat_message objects.
#' @param mode Character string, template mode.
#' @param add_assistant_prefix Logical, whether to add assistant prefix at end.
#' @return Character string.
#' @keywords internal
format_chat_messages <- function(messages, mode = "turbotoken_v1",
                                  add_assistant_prefix = TRUE) {
  template <- resolve_chat_template(mode)
  parts <- character(0)

  for (msg in messages) {
    parts <- c(parts, format_chat_role(template$message_prefix, msg$role))
    if (!is.null(msg$name)) {
      parts <- c(parts, paste0("name=", msg$name, "\n"))
    }
    parts <- c(parts, msg$content)
    parts <- c(parts, template$message_suffix)
  }

  if (add_assistant_prefix && !is.null(template$assistant_prefix)) {
    parts <- c(parts, template$assistant_prefix)
  }

  paste0(parts, collapse = "")
}
