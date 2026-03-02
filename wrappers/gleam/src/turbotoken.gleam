/// TurboToken - the fastest BPE tokenizer on every platform.
///
/// Drop-in replacement for tiktoken with identical output.
///
import turbotoken/encoding.{type Encoding}
import turbotoken/ffi
import turbotoken/rank_cache
import turbotoken/registry

/// Error types returned by turbotoken operations.
pub type TurbotokenError {
  UnknownEncoding(name: String)
  UnknownModel(model: String)
  EncodeFailed
  DecodeFailed
  CountFailed
  RankLoadFailed(reason: String)
  DownloadFailed(reason: String)
}

/// Get an encoding by name (e.g. "cl100k_base", "o200k_base").
pub fn get_encoding(name: String) -> Result(Encoding, TurbotokenError) {
  case registry.get_encoding_spec(name) {
    Ok(spec) ->
      case rank_cache.ensure_rank_file(name) {
        Ok(rank_payload) -> Ok(encoding.new(name, spec, rank_payload))
        Error(reason) -> Error(RankLoadFailed(reason))
      }
    Error(_) -> Error(UnknownEncoding(name))
  }
}

/// Get the encoding for a given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
pub fn get_encoding_for_model(
  model: String,
) -> Result(Encoding, TurbotokenError) {
  case registry.model_to_encoding(model) {
    Ok(encoding_name) -> get_encoding(encoding_name)
    Error(_) -> Error(UnknownModel(model))
  }
}

/// List all supported encoding names.
pub fn list_encoding_names() -> List(String) {
  registry.list_encoding_names()
}

/// Return the turbotoken native library version string.
pub fn version() -> String {
  ffi.version()
}
