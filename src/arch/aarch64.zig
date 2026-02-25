const builtin = @import("builtin");
const std = @import("std");

pub fn available() bool {
    return builtin.cpu.arch == .aarch64;
}

pub fn estimateTokenBound(text: []const u8) usize {
    if (text.len == 0) {
        return 0;
    }

    var non_ascii: usize = 0;
    var idx: usize = 0;

    const threshold: @Vector(16, u8) = @splat(0x80);
    while (idx + 16 <= text.len) : (idx += 16) {
        const chunk_bytes: [16]u8 = text[idx..][0..16].*;
        const chunk: @Vector(16, u8) = @bitCast(chunk_bytes);
        const mask = chunk >= threshold;
        inline for (0..16) |lane| {
            if (mask[lane]) {
                non_ascii += 1;
            }
        }
    }

    while (idx < text.len) : (idx += 1) {
        if (text[idx] & 0x80 != 0) {
            non_ascii += 1;
        }
    }

    const ascii = text.len - non_ascii;
    return ((ascii + 3) / 4) + non_ascii;
}

test "aarch64 estimate token bound handles ascii and utf8 bytes" {
    try std.testing.expectEqual(@as(usize, 0), estimateTokenBound(""));
    try std.testing.expectEqual(@as(usize, 2), estimateTokenBound("hello"));

    // "🚀" is four non-ASCII bytes in UTF-8, so this heuristic returns 4.
    try std.testing.expectEqual(@as(usize, 4), estimateTokenBound("🚀"));
    try std.testing.expectEqual(@as(usize, 5), estimateTokenBound("a🚀b"));
}
