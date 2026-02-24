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
    _ = exports.turbotoken_encode_utf8_bytes;
    _ = exports.turbotoken_decode_utf8_bytes;
}

test "scaffold compiles" {
    const enc = Encoder.init();
    const dec = Decoder.init();
    _ = enc;
    _ = dec;
}
