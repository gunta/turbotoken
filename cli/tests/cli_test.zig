const std = @import("std");
const tt = @import("turbotoken");

// Test the registry functions that are used by the CLI

test "encoding lookup for CLI default" {
    const spec = tt.getEncodingSpec("o200k_base");
    try std.testing.expect(spec != null);
    try std.testing.expectEqual(@as(u32, 200019), spec.?.n_vocab);
}

test "model flag resolution gpt-4o" {
    const enc = tt.modelToEncoding("gpt-4o");
    try std.testing.expect(enc != null);
    try std.testing.expect(std.mem.eql(u8, enc.?, "o200k_base"));
}

test "model flag resolution gpt-4" {
    const enc = tt.modelToEncoding("gpt-4");
    try std.testing.expect(enc != null);
    try std.testing.expect(std.mem.eql(u8, enc.?, "cl100k_base"));
}

test "model flag resolution gpt-3.5-turbo" {
    const enc = tt.modelToEncoding("gpt-3.5-turbo");
    try std.testing.expect(enc != null);
    try std.testing.expect(std.mem.eql(u8, enc.?, "cl100k_base"));
}

test "model flag resolution unknown returns null" {
    const enc = tt.modelToEncoding("unknown-model-xyz");
    try std.testing.expect(enc == null);
}

test "list-encodings has expected count" {
    const names = tt.listEncodingNames();
    try std.testing.expectEqual(@as(usize, 7), names.len);
}

test "all listed encodings are valid specs" {
    const names = tt.listEncodingNames();
    for (names) |name| {
        try std.testing.expect(tt.getEncodingSpec(name) != null);
    }
}

test "formatChat produces output with roles" {
    const allocator = std.testing.allocator;
    const messages = &[_]tt.ChatMessage{
        .{ .role = "system", .content = "You are helpful." },
        .{ .role = "user", .content = "Hello" },
    };

    const formatted = try tt.formatChat(allocator, messages, .{});
    defer allocator.free(formatted);

    try std.testing.expect(formatted.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "system") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "user") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "Hello") != null);
}

test "ChatOptions default encoding" {
    const opts = tt.ChatOptions{};
    try std.testing.expect(opts.add_generation_prompt);
    try std.testing.expect(std.mem.eql(u8, opts.generation_role, "assistant"));
}
