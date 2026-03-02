/// FFI bridge to the turbotoken NIF.
///
/// These external functions call into the Erlang NIF module
/// (Elixir.TurboToken.Nif) which is shared between Elixir and Gleam.

@external(erlang, "turbotoken_ffi", "version")
pub fn version() -> String

@external(erlang, "turbotoken_ffi", "encode_bpe")
pub fn encode_bpe(
  rank_payload: BitArray,
  text: String,
) -> Result(List(Int), String)

@external(erlang, "turbotoken_ffi", "decode_bpe")
pub fn decode_bpe(
  rank_payload: BitArray,
  tokens: List(Int),
) -> Result(BitArray, String)

@external(erlang, "turbotoken_ffi", "count_bpe")
pub fn count_bpe(
  rank_payload: BitArray,
  text: String,
) -> Result(Int, String)

@external(erlang, "turbotoken_ffi", "is_within_token_limit")
pub fn is_within_token_limit(
  rank_payload: BitArray,
  text: String,
  limit: Int,
) -> Result(Int, String)

@external(erlang, "turbotoken_ffi", "count_bpe_file")
pub fn count_bpe_file(
  rank_payload: BitArray,
  file_path: String,
) -> Result(Int, String)

@external(erlang, "turbotoken_ffi", "clear_rank_table_cache")
pub fn clear_rank_table_cache() -> Nil
