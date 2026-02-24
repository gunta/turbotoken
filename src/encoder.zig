const std = @import("std");

pub const Encoder = struct {
    pub fn init() Encoder {
        return .{};
    }

    pub fn encode(self: *const Encoder, allocator: std.mem.Allocator, text: []const u8) ![]u32 {
        _ = self;
        var out = try allocator.alloc(u32, text.len);
        for (text, 0..) |byte, idx| {
            out[idx] = byte;
        }
        return out;
    }
};
