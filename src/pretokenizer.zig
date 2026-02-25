const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");

pub fn estimateTokenBound(text: []const u8) usize {
    if (text.len == 0) {
        return 0;
    }

    if (builtin.cpu.arch == .aarch64 and aarch64.available()) {
        return aarch64.estimateTokenBound(text);
    }

    return (text.len + 3) / 4;
}

test "generic token bound heuristic remains stable on non-aarch64 paths" {
    try std.testing.expectEqual(@as(usize, 0), estimateTokenBound(""));
    try std.testing.expectEqual(@as(usize, 2), estimateTokenBound("hello"));
}
