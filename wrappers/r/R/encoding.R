#' Create a new turbotoken encoding object
#'
#' @param name Character string, encoding name.
#' @param spec List, encoding specification.
#' @param rank_payload Raw vector, rank file bytes.
#' @return An S3 object of class "turbotoken_encoding".
#' @keywords internal
new_encoding <- function(name, spec, rank_payload) {
  enc <- list(
    name = name,
    spec = spec,
    rank_payload = rank_payload
  )
  class(enc) <- "turbotoken_encoding"
  enc
}

#' Print method for turbotoken_encoding
#'
#' @param x A turbotoken_encoding object.
#' @param ... Additional arguments (ignored).
#' @export
print.turbotoken_encoding <- function(x, ...) {
  cat(sprintf('<Encoding "%s" n_vocab=%d>\n', x$name, x$spec$n_vocab))
  invisible(x)
}

#' Encode text to BPE tokens
#'
#' @param enc A turbotoken_encoding object.
#' @param text Character string to encode.
#' @return Integer vector of token IDs.
#' @export
encode <- function(enc, text) {
  UseMethod("encode")
}

#' @export
encode.turbotoken_encoding <- function(enc, text) {
  .Call(C_turbotoken_encode_bpe, enc$rank_payload, as.character(text))
}

#' Decode BPE tokens to text
#'
#' @param enc A turbotoken_encoding object.
#' @param tokens Integer vector of token IDs.
#' @return Character string.
#' @export
decode <- function(enc, tokens) {
  UseMethod("decode")
}

#' @export
decode.turbotoken_encoding <- function(enc, tokens) {
  .Call(C_turbotoken_decode_bpe, enc$rank_payload, as.integer(tokens))
}

#' Count BPE tokens in text
#'
#' @param enc A turbotoken_encoding object.
#' @param text Character string.
#' @return Integer, number of tokens.
#' @export
count_tokens <- function(enc, text) {
  UseMethod("count_tokens")
}

#' @export
count_tokens.turbotoken_encoding <- function(enc, text) {
  .Call(C_turbotoken_count_bpe, enc$rank_payload, as.character(text))
}

#' Check if text is within a token limit
#'
#' @param enc A turbotoken_encoding object.
#' @param text Character string.
#' @param limit Integer, maximum number of tokens.
#' @return Integer token count if within limit, NULL if exceeded.
#' @export
is_within_token_limit <- function(enc, text, limit) {
  UseMethod("is_within_token_limit")
}

#' @export
is_within_token_limit.turbotoken_encoding <- function(enc, text, limit) {
  .Call(C_turbotoken_is_within_limit, enc$rank_payload, as.character(text), as.integer(limit))
}

#' Encode chat messages to BPE tokens
#'
#' @param enc A turbotoken_encoding object.
#' @param messages A list of chat_message objects.
#' @param ... Additional options (mode, add_assistant_prefix).
#' @return Integer vector of token IDs.
#' @export
encode_chat <- function(enc, messages, ...) {
  UseMethod("encode_chat")
}

#' @export
encode_chat.turbotoken_encoding <- function(enc, messages, ...) {
  text <- format_chat_messages(messages, ...)
  encode(enc, text)
}

#' Count BPE tokens in chat messages
#'
#' @param enc A turbotoken_encoding object.
#' @param messages A list of chat_message objects.
#' @param ... Additional options.
#' @return Integer, number of tokens.
#' @export
count_chat <- function(enc, messages, ...) {
  UseMethod("count_chat")
}

#' @export
count_chat.turbotoken_encoding <- function(enc, messages, ...) {
  text <- format_chat_messages(messages, ...)
  count_tokens(enc, text)
}

#' Check if chat messages are within a token limit
#'
#' @param enc A turbotoken_encoding object.
#' @param messages A list of chat_message objects.
#' @param limit Integer, maximum number of tokens.
#' @param ... Additional options.
#' @return Integer token count if within limit, NULL if exceeded.
#' @export
is_chat_within_token_limit <- function(enc, messages, limit, ...) {
  UseMethod("is_chat_within_token_limit")
}

#' @export
is_chat_within_token_limit.turbotoken_encoding <- function(enc, messages, limit, ...) {
  text <- format_chat_messages(messages, ...)
  is_within_token_limit(enc, text, limit)
}

#' Encode a file's contents to BPE tokens
#'
#' @param enc A turbotoken_encoding object.
#' @param path Character string, file path.
#' @return Integer vector of token IDs.
#' @export
encode_file_path <- function(enc, path) {
  UseMethod("encode_file_path")
}

#' @export
encode_file_path.turbotoken_encoding <- function(enc, path) {
  .Call(C_turbotoken_encode_bpe_file, enc$rank_payload, as.character(path))
}

#' Count BPE tokens in a file
#'
#' @param enc A turbotoken_encoding object.
#' @param path Character string, file path.
#' @return Integer, number of tokens.
#' @export
count_file_path <- function(enc, path) {
  UseMethod("count_file_path")
}

#' @export
count_file_path.turbotoken_encoding <- function(enc, path) {
  .Call(C_turbotoken_count_bpe_file, enc$rank_payload, as.character(path))
}

#' Check if a file's content is within a token limit
#'
#' @param enc A turbotoken_encoding object.
#' @param path Character string, file path.
#' @param limit Integer, maximum number of tokens.
#' @return Integer token count if within limit, NULL if exceeded.
#' @export
is_file_path_within_token_limit <- function(enc, path, limit) {
  UseMethod("is_file_path_within_token_limit")
}

#' @export
is_file_path_within_token_limit.turbotoken_encoding <- function(enc, path, limit) {
  .Call(C_turbotoken_is_within_limit_file, enc$rank_payload, as.character(path), as.integer(limit))
}
