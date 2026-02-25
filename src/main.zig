pub const Encoder = @import("encoder.zig").Encoder;
pub const Decoder = @import("decoder.zig").Decoder;

pub const pretokenizer = @import("pretokenizer.zig");
pub const pair_cache = @import("pair_cache.zig");
pub const rank_loader = @import("rank_loader.zig");
pub const hash = @import("hash.zig");
pub const exports = @import("exports.zig");

comptime {
    _ = exports.turbotoken_version;
    _ = exports.turbotoken_count;
    _ = exports.turbotoken_arm64_feature_mask;
    _ = exports.turbotoken_count_non_ascii_kernel_id;
    _ = exports.turbotoken_count_non_ascii_utf8;
    _ = exports.turbotoken_count_non_ascii_utf8_scalar;
    _ = exports.turbotoken_count_non_ascii_utf8_neon;
    _ = exports.turbotoken_count_non_ascii_utf8_dotprod;
    _ = exports.turbotoken_count_non_ascii_utf8_sme;
    _ = exports.turbotoken_encode_utf8_bytes;
    _ = exports.turbotoken_decode_utf8_bytes;
    _ = exports.turbotoken_encode_bpe_from_ranks;
    _ = exports.turbotoken_encode_bpe_batch_from_ranks;
    _ = exports.turbotoken_encode_bpe_ranges_from_ranks;
    _ = exports.turbotoken_encode_bpe_chunked_stitched_from_ranks;
    _ = exports.turbotoken_count_bpe_from_ranks;
    _ = exports.turbotoken_decode_bpe_from_ranks;
}

test "scaffold compiles" {
    const enc = Encoder.init();
    const dec = Decoder.init();
    _ = enc;
    _ = dec;
}
