/// Encoding type and operations for BPE tokenization.
import turbotoken/ffi
import turbotoken/registry.{type EncodingSpec}

/// An opaque encoding with loaded rank data.
pub opaque type Encoding {
  Encoding(name: String, spec: EncodingSpec, rank_payload: BitArray)
}

/// Create a new Encoding (used internally by turbotoken.get_encoding).
pub fn new(name: String, spec: EncodingSpec, rank_payload: BitArray) -> Encoding {
  Encoding(name: name, spec: spec, rank_payload: rank_payload)
}

/// Get the name of this encoding.
pub fn name(enc: Encoding) -> String {
  enc.name
}

/// Encode text into a list of BPE token IDs.
pub fn encode(enc: Encoding, text: String) -> Result(List(Int), String) {
  ffi.encode_bpe(enc.rank_payload, text)
}

/// Decode a list of BPE token IDs back to a UTF-8 string.
pub fn decode(enc: Encoding, tokens: List(Int)) -> Result(BitArray, String) {
  ffi.decode_bpe(enc.rank_payload, tokens)
}

/// Count the number of BPE tokens in text without materializing the list.
pub fn count(enc: Encoding, text: String) -> Result(Int, String) {
  ffi.count_bpe(enc.rank_payload, text)
}

/// Alias for count.
pub fn count_tokens(enc: Encoding, text: String) -> Result(Int, String) {
  count(enc, text)
}

/// Check if text is within a token limit.
/// Returns Ok(count) if within limit, or Error("exceeded") if over.
pub fn is_within_token_limit(
  enc: Encoding,
  text: String,
  limit: Int,
) -> Result(Int, String) {
  ffi.is_within_token_limit(enc.rank_payload, text, limit)
}
