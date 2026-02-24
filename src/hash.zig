const std = @import("std");

pub fn bytes(input: []const u8) u64 {
    return std.hash.Wyhash.hash(0, input);
}
