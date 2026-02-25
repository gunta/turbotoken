const std = @import("std");
const rank_loader = @import("rank_loader.zig");

pub const Decoder = struct {
    pub fn init() Decoder {
        return .{};
    }

    pub fn decode(self: *const Decoder, allocator: std.mem.Allocator, tokens: []const u32) ![]u8 {
        _ = self;
        var out = try allocator.alloc(u8, tokens.len);
        for (tokens, 0..) |token, idx| {
            if (token > std.math.maxInt(u8)) {
                return error.InvalidToken;
            }
            out[idx] = @as(u8, @intCast(token));
        }
        return out;
    }

    pub fn decodeWithRanks(
        self: *const Decoder,
        allocator: std.mem.Allocator,
        tokens: []const u32,
        table: *const rank_loader.RankTable,
    ) ![]u8 {
        _ = self;

        var total_len: usize = 0;
        for (tokens) |token| {
            const token_bytes = table.tokenForRank(token) orelse return error.UnknownTokenRank;
            total_len += token_bytes.len;
        }

        var out = try allocator.alloc(u8, total_len);
        var cursor: usize = 0;
        for (tokens) |token| {
            const token_bytes = table.tokenForRank(token) orelse return error.UnknownTokenRank;
            @memcpy(out[cursor .. cursor + token_bytes.len], token_bytes);
            cursor += token_bytes.len;
        }

        return out;
    }
};

test "decodeWithRanks reconstructs token bytes" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const dec = Decoder.init();
    const out = try dec.decodeWithRanks(allocator, &[_]u32{ 2, 1 }, &table);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("abb", out);
}

test "decodeWithRanks errors on unknown rank" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const dec = Decoder.init();
    try std.testing.expectError(error.UnknownTokenRank, dec.decodeWithRanks(allocator, &[_]u32{42}, &table));
}
