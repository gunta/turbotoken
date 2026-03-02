require_relative "../lib/turbotoken"

RSpec.describe TurboToken do
  describe "Registry" do
    it "lists encoding names" do
      names = TurboToken.list_encoding_names
      expect(names).to be_an(Array)
      expect(names.length).to eq(7)
      expect(names).to eq(names.sort)
      expect(names).to include("cl100k_base", "o200k_base", "gpt2")
    end

    it "gets encoding spec for known encoding" do
      spec = TurboToken::Registry.get_encoding_spec("cl100k_base")
      expect(spec.name).to eq("cl100k_base")
      expect(spec.explicit_n_vocab).to eq(100_277)
      expect(spec.special_tokens).to have_key("<|endoftext|>")
    end

    it "raises for unknown encoding" do
      expect {
        TurboToken::Registry.get_encoding_spec("nonexistent")
      }.to raise_error(TurboToken::Error, /Unknown encoding/)
    end

    it "maps model to encoding" do
      expect(TurboToken::Registry.model_to_encoding("gpt-4o")).to eq("o200k_base")
      expect(TurboToken::Registry.model_to_encoding("gpt-4")).to eq("cl100k_base")
    end

    it "maps model prefix to encoding" do
      expect(TurboToken::Registry.model_to_encoding("gpt-4o-2024-01-01")).to eq("o200k_base")
      expect(TurboToken::Registry.model_to_encoding("gpt-4-turbo")).to eq("cl100k_base")
    end

    it "raises for unknown model" do
      expect {
        TurboToken::Registry.model_to_encoding("unknown-model")
      }.to raise_error(TurboToken::Error, /Could not automatically map/)
    end
  end

  describe "Encoding", :nif do
    let(:encoding) { TurboToken.get_encoding("cl100k_base") }

    it "encodes and decodes round trip" do
      text = "Hello, world!"
      tokens = encoding.encode(text)
      expect(tokens).to be_an(Array)
      expect(tokens.length).to be > 0
      decoded = encoding.decode(tokens)
      expect(decoded).to eq(text)
    end

    it "counts tokens" do
      count = encoding.count("Hello, world!")
      expect(count).to be_an(Integer)
      expect(count).to be > 0
    end

    it "gets encoding by name" do
      enc = TurboToken.get_encoding("o200k_base")
      expect(enc.name).to eq("o200k_base")
    end

    it "gets encoding for model" do
      enc = TurboToken.get_encoding_for_model("gpt-4o")
      expect(enc.name).to eq("o200k_base")
    end
  end
end
