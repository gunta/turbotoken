require "ffi"

module TurboToken
  module FFIBridge
    extend FFI::Library

    # Library search order:
    # 1. TURBOTOKEN_NATIVE_LIB env var (explicit path)
    # 2. Bundled in gem (lib/turbotoken/)
    # 3. System library path
    # 4. zig-out/lib/ (development)
    LIB_SEARCH_PATHS = [
      ENV["TURBOTOKEN_NATIVE_LIB"],
      File.join(__dir__, "libturbotoken"),
      "turbotoken",
      File.expand_path("../../../../zig-out/lib/libturbotoken", __dir__),
    ].compact

    ffi_lib LIB_SEARCH_PATHS

    # Version
    attach_function :turbotoken_version, [], :string

    # Cache management
    attach_function :turbotoken_clear_rank_table_cache, [], :void

    # BPE encode: (rank_bytes, rank_len, text, text_len, out_tokens, out_cap) -> count
    attach_function :turbotoken_encode_bpe_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t, :pointer, :size_t],
                    :ssize_t

    # BPE decode: (rank_bytes, rank_len, tokens, token_len, out_bytes, out_cap) -> count
    attach_function :turbotoken_decode_bpe_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t, :pointer, :size_t],
                    :ssize_t

    # BPE count: (rank_bytes, rank_len, text, text_len) -> count
    attach_function :turbotoken_count_bpe_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t],
                    :ssize_t

    # BPE is_within_token_limit: (rank_bytes, rank_len, text, text_len, limit) -> result
    attach_function :turbotoken_is_within_token_limit_bpe_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t, :size_t],
                    :ssize_t

    # BPE count file: (rank_bytes, rank_len, file_path, file_path_len) -> count
    attach_function :turbotoken_count_bpe_file_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t],
                    :ssize_t

    # BPE encode file: (rank_bytes, rank_len, file_path, file_path_len, out_tokens, out_cap) -> count
    attach_function :turbotoken_encode_bpe_file_from_ranks,
                    [:pointer, :size_t, :pointer, :size_t, :pointer, :size_t],
                    :ssize_t

    # Training
    attach_function :turbotoken_train_bpe_from_chunk_counts,
                    [:pointer, :size_t, :pointer, :size_t, :pointer, :size_t,
                     :uint32, :uint32, :pointer, :size_t],
                    :ssize_t
  end
end
