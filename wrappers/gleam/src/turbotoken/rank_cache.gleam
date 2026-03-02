/// Downloads and caches BPE rank files.
import gleam/erlang/os
import turbotoken/registry

/// Get the cache directory path.
pub fn cache_dir() -> String {
  case os.get_env("TURBOTOKEN_CACHE_DIR") {
    Ok(dir) -> dir
    Error(_) ->
      case os.get_env("XDG_CACHE_HOME") {
        Ok(xdg) -> xdg <> "/turbotoken"
        Error(_) -> home_dir() <> "/.cache/turbotoken"
      }
  }
}

/// Ensure the rank file for the given encoding exists and return its contents.
pub fn ensure_rank_file(name: String) -> Result(BitArray, String) {
  case registry.get_encoding_spec(name) {
    Ok(spec) -> {
      let path = cache_dir() <> "/" <> name <> ".tiktoken"
      case read_file(path) {
        Ok(data) -> Ok(data)
        Error(_) -> download_and_cache(spec.rank_file_url, path)
      }
    }
    Error(reason) -> Error(reason)
  }
}

/// Read a rank file from disk.
pub fn read_rank_file(path: String) -> Result(BitArray, String) {
  read_file(path)
}

@external(erlang, "turbotoken_ffi", "read_file")
fn read_file(path: String) -> Result(BitArray, String)

@external(erlang, "turbotoken_ffi", "download_and_cache")
fn download_and_cache(
  url: String,
  dest_path: String,
) -> Result(BitArray, String)

@external(erlang, "turbotoken_ffi", "home_dir")
fn home_dir() -> String
