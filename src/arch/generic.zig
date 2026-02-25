const std = @import("std");
const Encoder = @import("../encoder.zig").Encoder;
const Decoder = @import("../decoder.zig").Decoder;
const rank_loader = @import("../rank_loader.zig");

pub fn available() bool {
    return true;
}

pub const ScalarBackend = struct {
    encoder: Encoder,
    decoder: Decoder,

    pub fn init() ScalarBackend {
        return .{
            .encoder = Encoder.init(),
            .decoder = Decoder.init(),
        };
    }

    pub fn encode(
        self: *const ScalarBackend,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) ![]u32 {
        return self.encoder.encodeWithRanks(allocator, text, table);
    }

    pub fn decode(
        self: *const ScalarBackend,
        allocator: std.mem.Allocator,
        tokens: []const u32,
        table: *const rank_loader.RankTable,
    ) ![]u8 {
        return self.decoder.decodeWithRanks(allocator, tokens, table);
    }

    pub fn count(
        self: *const ScalarBackend,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) !usize {
        const tokens = try self.encode(allocator, text, table);
        defer allocator.free(tokens);
        return tokens.len;
    }
};

test "scalar backend roundtrip with rank table" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const backend = ScalarBackend.init();

    const tokens = try backend.encode(allocator, "abb", &table);
    defer allocator.free(tokens);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1 }, tokens);

    const text = try backend.decode(allocator, tokens, &table);
    defer allocator.free(text);
    try std.testing.expectEqualStrings("abb", text);

    try std.testing.expectEqual(@as(usize, 2), try backend.count(allocator, "abb", &table));
}
