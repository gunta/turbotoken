const std = @import("std");

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
};
