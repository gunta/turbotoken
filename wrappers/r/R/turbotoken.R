#' Get a BPE encoding by name
#'
#' @param name Character string, encoding name (e.g. "cl100k_base", "o200k_base").
#' @return A turbotoken_encoding object.
#' @export
get_encoding <- function(name) {
  spec <- get_encoding_spec(name)
  rank_payload <- read_rank_file(name)
  new_encoding(name, spec, rank_payload)
}

#' Get the appropriate BPE encoding for a model
#'
#' @param model Character string, model name (e.g. "gpt-4o", "gpt-3.5-turbo").
#' @return A turbotoken_encoding object.
#' @export
get_encoding_for_model <- function(model) {
  enc_name <- model_to_encoding_name(model)
  get_encoding(enc_name)
}

#' Get the turbotoken native library version
#'
#' @return Character string, version of the native library.
#' @export
tt_version <- function() {
  .Call(C_turbotoken_version)
}
