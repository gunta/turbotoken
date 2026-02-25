const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const ScalarBackend = @import("arch/generic.zig").ScalarBackend;
const rank_loader = @import("rank_loader.zig");

const RankTableCache = struct {
    hash: u64 = 0,
    payload: ?[]u8 = null,
    last_input_ptr: usize = 0,
    last_input_len: usize = 0,
    table: ?rank_loader.RankTable = null,
};

var rank_table_cache: RankTableCache = .{};

fn clearRankTableCache() void {
    if (rank_table_cache.table) |*table| {
        table.deinit();
        rank_table_cache.table = null;
    }
    if (rank_table_cache.payload) |payload| {
        std.heap.c_allocator.free(payload);
        rank_table_cache.payload = null;
    }
    rank_table_cache.hash = 0;
    rank_table_cache.last_input_ptr = 0;
    rank_table_cache.last_input_len = 0;
}

fn ensureCachedRankTable(rank_slice: []const u8) !*const rank_loader.RankTable {
    const input_ptr = @intFromPtr(rank_slice.ptr);
    const input_len = rank_slice.len;

    if (rank_table_cache.table != null and
        rank_table_cache.last_input_ptr == input_ptr and
        rank_table_cache.last_input_len == input_len)
    {
        return &rank_table_cache.table.?;
    }

    const hash = std.hash.Wyhash.hash(0, rank_slice);

    if (rank_table_cache.payload) |payload| {
        if (rank_table_cache.hash == hash and payload.len == input_len and std.mem.eql(u8, payload, rank_slice)) {
            rank_table_cache.last_input_ptr = input_ptr;
            rank_table_cache.last_input_len = input_len;
            return &rank_table_cache.table.?;
        }
    }

    clearRankTableCache();

    const payload_copy = try std.heap.c_allocator.alloc(u8, rank_slice.len);
    errdefer std.heap.c_allocator.free(payload_copy);
    @memcpy(payload_copy, rank_slice);

    var table = try rank_loader.loadFromBytes(std.heap.c_allocator, rank_slice);
    errdefer table.deinit();

    rank_table_cache.hash = hash;
    rank_table_cache.payload = payload_copy;
    rank_table_cache.last_input_ptr = input_ptr;
    rank_table_cache.last_input_len = input_len;
    rank_table_cache.table = table;
    return &(rank_table_cache.table.?);
}

pub export fn turbotoken_version() [*c]const u8 {
    return "0.1.0-dev";
}

pub export fn turbotoken_count(_: [*c]const u8, text_len: usize) isize {
    if (text_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(text_len));
}

fn encodeUtf8BytesScalar(in_slice: []const u8, out_slice: []u32) void {
    for (in_slice, 0..) |byte, idx| {
        out_slice[idx] = byte;
    }
}

fn decodeUtf8BytesScalar(in_slice: []const u32, out_slice: []u8) bool {
    for (in_slice, 0..) |token, idx| {
        if (token > std.math.maxInt(u8)) {
            return false;
        }
        out_slice[idx] = @as(u8, @intCast(token));
    }
    return true;
}

pub export fn turbotoken_encode_utf8_bytes(
    text: [*c]const u8,
    text_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (out_tokens == null) {
        if (text_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(text_len));
    }

    if (out_cap < text_len) {
        return -1;
    }

    const in_slice = text[0..text_len];
    const out_slice = out_tokens[0..text_len];

    if (builtin.cpu.arch == .aarch64 and aarch64.available() and text_len >= 16) {
        aarch64.encodeU8ToU32(in_slice, out_slice);
        return @as(isize, @intCast(text_len));
    }

    encodeUtf8BytesScalar(in_slice, out_slice);
    return @as(isize, @intCast(text_len));
}

pub export fn turbotoken_encode_utf8_bytes_scalar(
    text: [*c]const u8,
    text_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (out_tokens == null) {
        if (text_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(text_len));
    }

    if (out_cap < text_len) {
        return -1;
    }

    const in_slice = text[0..text_len];
    const out_slice = out_tokens[0..text_len];
    encodeUtf8BytesScalar(in_slice, out_slice);
    return @as(isize, @intCast(text_len));
}

pub export fn turbotoken_decode_utf8_bytes(
    tokens: [*c]const u32,
    token_len: usize,
    out_bytes: [*c]u8,
    out_cap: usize,
) isize {
    if (out_bytes == null) {
        if (token_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }

    if (out_cap < token_len) {
        return -1;
    }

    const in_slice = tokens[0..token_len];
    const out_slice = out_bytes[0..token_len];

    if (builtin.cpu.arch == .aarch64 and aarch64.available() and token_len >= 16) {
        if (!aarch64.validateAndDecodeU32ToU8(in_slice, out_slice)) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }

    if (!decodeUtf8BytesScalar(in_slice, out_slice)) {
        return -1;
    }

    return @as(isize, @intCast(token_len));
}

pub export fn turbotoken_decode_utf8_bytes_scalar(
    tokens: [*c]const u32,
    token_len: usize,
    out_bytes: [*c]u8,
    out_cap: usize,
) isize {
    if (out_bytes == null) {
        if (token_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }

    if (out_cap < token_len) {
        return -1;
    }

    const in_slice = tokens[0..token_len];
    const out_slice = out_bytes[0..token_len];
    if (!decodeUtf8BytesScalar(in_slice, out_slice)) {
        return -1;
    }

    return @as(isize, @intCast(token_len));
}

pub export fn turbotoken_encode_bpe_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (rank_bytes == null or text == null) {
        return -1;
    }

    const allocator = std.heap.page_allocator;
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;

    const backend = ScalarBackend.init();
    const tokens = backend.encode(allocator, text[0..text_len], table) catch return -1;
    defer allocator.free(tokens);

    if (out_tokens == null) {
        if (tokens.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(tokens.len));
    }

    if (out_cap < tokens.len) {
        return -1;
    }

    @memcpy(out_tokens[0..tokens.len], tokens);
    return @as(isize, @intCast(tokens.len));
}

pub export fn turbotoken_count_bpe_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (rank_bytes == null or text == null) {
        return -1;
    }

    const allocator = std.heap.page_allocator;
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;

    const backend = ScalarBackend.init();
    const token_count = backend.count(allocator, text[0..text_len], table) catch return -1;
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

pub export fn turbotoken_decode_bpe_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    tokens: [*c]const u32,
    token_len: usize,
    out_bytes: [*c]u8,
    out_cap: usize,
) isize {
    if (rank_bytes == null or tokens == null) {
        return -1;
    }

    const allocator = std.heap.page_allocator;
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;

    const backend = ScalarBackend.init();
    const bytes = backend.decode(allocator, tokens[0..token_len], table) catch return -1;
    defer allocator.free(bytes);

    if (out_bytes == null) {
        if (bytes.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(bytes.len));
    }

    if (out_cap < bytes.len) {
        return -1;
    }

    @memcpy(out_bytes[0..bytes.len], bytes);
    return @as(isize, @intCast(bytes.len));
}

test "count returns byte length for placeholder path" {
    const text = "hello";
    try std.testing.expectEqual(@as(isize, 5), turbotoken_count(text.ptr, text.len));
}

test "encode/decode utf8 byte placeholder path" {
    const text = "abc";
    var tokens: [3]u32 = undefined;
    var out: [3]u8 = undefined;

    const encoded = turbotoken_encode_utf8_bytes(text.ptr, text.len, &tokens, tokens.len);
    try std.testing.expectEqual(@as(isize, 3), encoded);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 97, 98, 99 }, &tokens);

    const decoded = turbotoken_decode_utf8_bytes(&tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, 3), decoded);
    try std.testing.expectEqualSlices(u8, "abc", &out);
}

test "encode/decode utf8 byte placeholder path handles vector-sized input" {
    const text = "0123456789abcdef0123456789abcdef";
    var tokens: [text.len]u32 = undefined;
    var out: [text.len]u8 = undefined;

    const encoded = turbotoken_encode_utf8_bytes(text.ptr, text.len, &tokens, tokens.len);
    try std.testing.expectEqual(@as(isize, text.len), encoded);
    for (text, 0..) |byte, idx| {
        try std.testing.expectEqual(@as(u32, byte), tokens[idx]);
    }

    const decoded = turbotoken_decode_utf8_bytes(&tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, text.len), decoded);
    try std.testing.expectEqualSlices(u8, text, &out);
}

test "decode utf8 byte placeholder path rejects invalid token in vector-sized input" {
    var tokens = [_]u32{65} ** 16;
    tokens[9] = 999;
    var out: [16]u8 = undefined;
    const decoded = turbotoken_decode_utf8_bytes(&tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, -1), decoded);
}

test "scalar utf8 byte exports match placeholder behavior" {
    const text = "0123456789abcdef0123456789abcdef";
    var tokens: [text.len]u32 = undefined;
    var out: [text.len]u8 = undefined;

    const encoded = turbotoken_encode_utf8_bytes_scalar(text.ptr, text.len, &tokens, tokens.len);
    try std.testing.expectEqual(@as(isize, text.len), encoded);
    for (text, 0..) |byte, idx| {
        try std.testing.expectEqual(@as(u32, byte), tokens[idx]);
    }

    const decoded = turbotoken_decode_utf8_bytes_scalar(&tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, text.len), decoded);
    try std.testing.expectEqualSlices(u8, text, &out);

    tokens[5] = 999;
    const invalid = turbotoken_decode_utf8_bytes_scalar(&tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, -1), invalid);
}

test "encode/decode bpe path using provided ranks" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const needed = turbotoken_encode_bpe_from_ranks(ranks.ptr, ranks.len, "abb".ptr, 3, null, 0);
    try std.testing.expectEqual(@as(isize, 2), needed);

    const count = turbotoken_count_bpe_from_ranks(ranks.ptr, ranks.len, "abb".ptr, 3);
    try std.testing.expectEqual(@as(isize, 2), count);

    var tokens: [2]u32 = undefined;
    const written = turbotoken_encode_bpe_from_ranks(ranks.ptr, ranks.len, "abb".ptr, 3, &tokens, tokens.len);
    try std.testing.expectEqual(@as(isize, 2), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1 }, &tokens);

    const bytes_needed = turbotoken_decode_bpe_from_ranks(ranks.ptr, ranks.len, &tokens, tokens.len, null, 0);
    try std.testing.expectEqual(@as(isize, 3), bytes_needed);

    var out: [3]u8 = undefined;
    const decoded = turbotoken_decode_bpe_from_ranks(ranks.ptr, ranks.len, &tokens, tokens.len, &out, out.len);
    try std.testing.expectEqual(@as(isize, 3), decoded);
    try std.testing.expectEqualSlices(u8, "abb", &out);
}

test "rank-table cache reuses parsed table for same input pointer" {
    clearRankTableCache();
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const table_a = try ensureCachedRankTable(ranks);
    const table_a_ptr = @intFromPtr(table_a);
    try std.testing.expect(rank_table_cache.last_input_ptr == @intFromPtr(ranks.ptr));
    try std.testing.expectEqual(ranks.len, rank_table_cache.last_input_len);

    const table_b = try ensureCachedRankTable(ranks);
    try std.testing.expectEqual(table_a_ptr, @intFromPtr(table_b));
}

test "rank-table cache reuses parsed table for same payload bytes" {
    clearRankTableCache();
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;
    const allocator = std.testing.allocator;

    _ = try ensureCachedRankTable(ranks);
    const initial_table_ptr = @intFromPtr(&rank_table_cache.table.?);

    const copied = try allocator.dupe(u8, ranks);
    defer allocator.free(copied);
    try std.testing.expect(@intFromPtr(copied.ptr) != @intFromPtr(ranks.ptr));

    const table_b = try ensureCachedRankTable(copied);
    try std.testing.expectEqual(initial_table_ptr, @intFromPtr(table_b));
}
