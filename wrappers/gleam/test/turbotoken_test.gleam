import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import turbotoken/registry

pub fn main() {
  gleeunit.main()
}

pub fn list_encoding_names_test() {
  let names = registry.list_encoding_names()
  list.length(names) |> should.equal(7)

  // Should be sorted
  let sorted = list.sort(names, string.compare)
  names |> should.equal(sorted)

  // Should contain key encodings
  list.contains(names, "cl100k_base") |> should.be_true()
  list.contains(names, "o200k_base") |> should.be_true()
  list.contains(names, "gpt2") |> should.be_true()
}

pub fn get_encoding_spec_known_test() {
  let assert Ok(spec) = registry.get_encoding_spec("cl100k_base")
  spec.name |> should.equal("cl100k_base")
  spec.explicit_n_vocab |> should.equal(100_277)
}

pub fn get_encoding_spec_unknown_test() {
  let result = registry.get_encoding_spec("nonexistent")
  should.be_error(result)
}

pub fn model_to_encoding_known_test() {
  let assert Ok(enc) = registry.model_to_encoding("gpt-4o")
  enc |> should.equal("o200k_base")

  let assert Ok(enc2) = registry.model_to_encoding("gpt-4")
  enc2 |> should.equal("cl100k_base")
}

pub fn model_to_encoding_prefix_test() {
  let assert Ok(enc) = registry.model_to_encoding("gpt-4o-2024-01-01")
  enc |> should.equal("o200k_base")

  let assert Ok(enc2) = registry.model_to_encoding("gpt-4-turbo")
  enc2 |> should.equal("cl100k_base")
}

pub fn model_to_encoding_unknown_test() {
  let result = registry.model_to_encoding("unknown-model")
  should.be_error(result)
}
