const std = @import("std");
const ScalarBackend = @import("arch/generic.zig").ScalarBackend;
const rank_loader = @import("rank_loader.zig");

const RankTableCache = struct {
    hash: u64 = 0,
    payload: ?[]u8 = null,
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
}

fn ensureCachedRankTable(rank_slice: []const u8) !*const rank_loader.RankTable {
    const hash = std.hash.Wyhash.hash(0, rank_slice);

    if (rank_table_cache.payload) |payload| {
        if (rank_table_cache.hash == hash and std.mem.eql(u8, payload, rank_slice)) {
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
    for (in_slice, 0..) |byte, idx| {
        out_slice[idx] = byte;
    }
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
    for (in_slice, 0..) |token, idx| {
        if (token > std.math.maxInt(u8)) {
            return -1;
        }
        out_slice[idx] = @as(u8, @intCast(token));
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
