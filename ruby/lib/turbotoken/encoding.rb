module TurboToken
  class Encoding
    attr_reader :name, :spec, :rank_payload

    def initialize(name, spec, rank_payload)
      @name = name
      @spec = spec
      @rank_payload = rank_payload
    end

    # Encode text into a list of BPE token IDs.
    def encode(text)
      text_bytes = text.encode("UTF-8")
      rank_ptr = ffi_ptr(@rank_payload)
      text_ptr = ffi_ptr(text_bytes)

      # Pass 1: query needed size
      needed = FFIBridge.turbotoken_encode_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        text_ptr, text_bytes.bytesize,
        nil, 0
      )
      raise Error, "encode failed" if needed < 0
      return [] if needed == 0

      # Pass 2: fill buffer
      out = FFI::MemoryPointer.new(:uint32, needed)
      written = FFIBridge.turbotoken_encode_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        text_ptr, text_bytes.bytesize,
        out, needed
      )
      raise Error, "encode failed (pass 2)" if written < 0

      out.read_array_of_uint32(written)
    end

    # Decode a list of BPE token IDs back to a UTF-8 string.
    def decode(tokens)
      rank_ptr = ffi_ptr(@rank_payload)
      tokens_ptr = FFI::MemoryPointer.new(:uint32, tokens.length)
      tokens_ptr.write_array_of_uint32(tokens)

      # Pass 1: query needed size
      needed = FFIBridge.turbotoken_decode_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        tokens_ptr, tokens.length,
        nil, 0
      )
      raise Error, "decode failed" if needed < 0
      return "".encode("UTF-8") if needed == 0

      # Pass 2: fill buffer
      out = FFI::MemoryPointer.new(:uint8, needed)
      written = FFIBridge.turbotoken_decode_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        tokens_ptr, tokens.length,
        out, needed
      )
      raise Error, "decode failed (pass 2)" if written < 0

      out.read_bytes(written).force_encoding("UTF-8")
    end

    # Count the number of BPE tokens in text without materializing.
    def count(text)
      text_bytes = text.encode("UTF-8")
      rank_ptr = ffi_ptr(@rank_payload)
      text_ptr = ffi_ptr(text_bytes)

      result = FFIBridge.turbotoken_count_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        text_ptr, text_bytes.bytesize
      )
      raise Error, "count failed" if result < 0
      result
    end

    alias_method :count_tokens, :count

    # Check if text is within a token limit.
    # Returns the token count if within limit, false if exceeded.
    def within_token_limit?(text, limit)
      text_bytes = text.encode("UTF-8")
      rank_ptr = ffi_ptr(@rank_payload)
      text_ptr = ffi_ptr(text_bytes)

      result = FFIBridge.turbotoken_is_within_token_limit_bpe_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        text_ptr, text_bytes.bytesize,
        limit
      )
      return false if result == -2
      raise Error, "token limit check failed" if result < 0
      result
    end

    # Encode a list of chat messages into token IDs.
    def encode_chat(messages, **opts)
      Chat.encode_chat(self, messages, **opts)
    end

    # Count tokens in a list of chat messages.
    def count_chat(messages, **opts)
      Chat.count_chat(self, messages, **opts)
    end

    # Check if chat messages are within a token limit.
    def chat_within_token_limit?(messages, limit, **opts)
      count = count_chat(messages, **opts)
      count <= limit ? count : false
    end

    # Encode a file's contents into token IDs.
    def encode_file_path(path)
      encode(File.read(path, encoding: "UTF-8"))
    end

    # Count tokens in a file using the native file counting path.
    def count_file_path(path)
      rank_ptr = ffi_ptr(@rank_payload)
      path_bytes = path.encode("UTF-8")
      path_ptr = ffi_ptr(path_bytes)

      result = FFIBridge.turbotoken_count_bpe_file_from_ranks(
        rank_ptr, @rank_payload.bytesize,
        path_ptr, path_bytes.bytesize
      )
      raise Error, "file count failed" if result < 0
      result
    end

    private

    def ffi_ptr(data)
      ptr = FFI::MemoryPointer.new(:uint8, data.bytesize)
      ptr.put_bytes(0, data)
      ptr
    end
  end
end
