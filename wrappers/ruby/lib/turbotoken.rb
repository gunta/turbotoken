require_relative "turbotoken/version"
require_relative "turbotoken/ffi_bridge"
require_relative "turbotoken/registry"
require_relative "turbotoken/rank_cache"
require_relative "turbotoken/encoding"
require_relative "turbotoken/chat"

module TurboToken
  class Error < StandardError; end

  # Get an encoding by name (e.g. "cl100k_base", "o200k_base").
  def self.get_encoding(name)
    spec = Registry.get_encoding_spec(name)
    rank_payload = RankCache.ensure_rank_file(name)
    Encoding.new(name, spec, rank_payload)
  end

  # Get the encoding for a given model name (e.g. "gpt-4o", "gpt-3.5-turbo").
  def self.get_encoding_for_model(model)
    encoding_name = Registry.model_to_encoding(model)
    get_encoding(encoding_name)
  end

  # List all supported encoding names.
  def self.list_encoding_names
    Registry.list_encoding_names
  end

  # Return the turbotoken native library version string.
  def self.version
    FFIBridge.turbotoken_version
  end
end
