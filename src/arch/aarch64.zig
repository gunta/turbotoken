const builtin = @import("builtin");
const std = @import("std");

extern fn turbotoken_arm64_count_non_ascii(bytes: [*]const u8, len: usize) usize;
extern fn turbotoken_arm64_decode_u32_to_u8(tokens: [*]const u32, len: usize, out: [*]u8) void;

pub fn available() bool {
    return builtin.cpu.arch == .aarch64;
}

pub fn decodeU32ToU8(tokens: []const u32, out: []u8) void {
    std.debug.assert(tokens.len == out.len);
    if (tokens.len == 0) {
        return;
    }
    turbotoken_arm64_decode_u32_to_u8(tokens.ptr, tokens.len, out.ptr);
}

pub fn estimateTokenBound(text: []const u8) usize {
    if (text.len == 0) {
        return 0;
    }

    const non_ascii = turbotoken_arm64_count_non_ascii(text.ptr, text.len);
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

test "aarch64 decoder packs u32 bytes" {
    var out: [4]u8 = undefined;
    decodeU32ToU8(&[_]u32{ 65, 66, 67, 68 }, &out);
    try std.testing.expectEqualSlices(u8, "ABCD", &out);
}
