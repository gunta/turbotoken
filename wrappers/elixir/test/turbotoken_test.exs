defmodule TurboTokenTest do
  use ExUnit.Case, async: true

  describe "Registry" do
    test "list_encoding_names returns sorted list" do
      names = TurboToken.list_encoding_names()
      assert is_list(names)
      assert length(names) == 7
      assert names == Enum.sort(names)
      assert "cl100k_base" in names
      assert "o200k_base" in names
    end

    test "get_encoding_spec for known encoding" do
      {:ok, spec} = TurboToken.Registry.get_encoding_spec("cl100k_base")
      assert spec.name == "cl100k_base"
      assert spec.explicit_n_vocab == 100_277
      assert Map.has_key?(spec.special_tokens, "<|endoftext|>")
    end

    test "get_encoding_spec for unknown encoding returns error" do
      assert {:error, {:unknown_encoding, "nonexistent", _}} =
               TurboToken.Registry.get_encoding_spec("nonexistent")
    end

    test "model_to_encoding for known model" do
      assert {:ok, "o200k_base"} = TurboToken.Registry.model_to_encoding("gpt-4o")
      assert {:ok, "cl100k_base"} = TurboToken.Registry.model_to_encoding("gpt-4")
    end

    test "model_to_encoding for prefix match" do
      assert {:ok, "o200k_base"} = TurboToken.Registry.model_to_encoding("gpt-4o-2024-01-01")
      assert {:ok, "cl100k_base"} = TurboToken.Registry.model_to_encoding("gpt-4-turbo")
    end

    test "model_to_encoding for unknown model returns error" do
      assert {:error, {:unknown_model, "unknown-model"}} =
               TurboToken.Registry.model_to_encoding("unknown-model")
    end
  end

  describe "Encoding (requires NIF)" do
    @tag :nif
    test "encode and decode round trip" do
      {:ok, enc} = TurboToken.get_encoding("cl100k_base")
      text = "Hello, world!"
      {:ok, tokens} = TurboToken.Encoding.encode(enc, text)
      assert is_list(tokens)
      assert length(tokens) > 0
      {:ok, decoded} = TurboToken.Encoding.decode(enc, tokens)
      assert decoded == text
    end

    @tag :nif
    test "count returns positive integer" do
      {:ok, enc} = TurboToken.get_encoding("cl100k_base")
      {:ok, count} = TurboToken.Encoding.count(enc, "Hello, world!")
      assert is_integer(count)
      assert count > 0
    end

    @tag :nif
    test "get_encoding by name" do
      {:ok, enc} = TurboToken.get_encoding("o200k_base")
      assert enc.name == "o200k_base"
    end

    @tag :nif
    test "get_encoding_for_model" do
      {:ok, enc} = TurboToken.get_encoding_for_model("gpt-4o")
      assert enc.name == "o200k_base"
    end
  end
end
