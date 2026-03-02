#' Get the cache directory for rank files
#'
#' Uses TURBOTOKEN_CACHE_DIR env var or defaults to ~/.cache/turbotoken/.
#'
#' @return Character string, path to cache directory.
#' @keywords internal
cache_dir <- function() {
  dir <- Sys.getenv("TURBOTOKEN_CACHE_DIR", unset = "")
  if (nchar(dir) == 0) {
    dir <- file.path(path.expand("~"), ".cache", "turbotoken")
  }
  dir
}

#' Ensure a rank file is downloaded and cached
#'
#' @param name Character string, encoding name.
#' @return Character string, path to the cached rank file.
#' @keywords internal
ensure_rank_file <- function(name) {
  spec <- get_encoding_spec(name)
  dir <- cache_dir()
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }
  filepath <- file.path(dir, paste0(spec$name, ".tiktoken"))

  if (!file.exists(filepath)) {
    message(sprintf("Downloading rank file for %s...", spec$name))
    utils::download.file(spec$rank_file_url, filepath, mode = "wb", quiet = TRUE)
  }

  filepath
}

#' Read rank file bytes
#'
#' @param name Character string, encoding name.
#' @return Raw vector of rank file bytes.
#' @keywords internal
read_rank_file <- function(name) {
  filepath <- ensure_rank_file(name)
  readBin(filepath, "raw", file.info(filepath)$size)
}
