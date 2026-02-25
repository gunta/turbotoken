const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const ScalarBackend = @import("arch/generic.zig").ScalarBackend;
const rank_loader = @import("rank_loader.zig");
const pretokenizer = @import("pretokenizer.zig");

const rank_cache_allocator = std.heap.page_allocator;

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
        rank_cache_allocator.free(payload);
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

    const payload_copy = try rank_cache_allocator.alloc(u8, rank_slice.len);
    errdefer rank_cache_allocator.free(payload_copy);
    @memcpy(payload_copy, rank_slice);

    var table = try rank_loader.loadFromBytes(rank_cache_allocator, rank_slice);
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

pub export fn turbotoken_pretokenize_ascii_letter_space_ranges(
    text: [*c]const u8,
    text_len: usize,
    out_starts: [*c]u32,
    out_ends: [*c]u32,
    out_cap: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }

    const in_slice = text[0..text_len];

    if (out_starts == null or out_ends == null) {
        const needed = pretokenizer.splitAsciiLetterSpaceRanges(in_slice, null, null) catch return -1;
        if (needed > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(needed));
    }

    const starts = out_starts[0..out_cap];
    const ends = out_ends[0..out_cap];
    const written = pretokenizer.splitAsciiLetterSpaceRanges(in_slice, starts, ends) catch return -1;
    if (written > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(written));
}

fn countNonAsciiScalar(in_slice: []const u8) usize {
    var count: usize = 0;
    for (in_slice) |byte| {
        count += @intFromBool((byte & 0x80) != 0);
    }
    return count;
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

pub export fn turbotoken_arm64_feature_mask() u64 {
    if (builtin.cpu.arch != .aarch64 or !aarch64.available()) {
        return 0;
    }
    return aarch64.featureMask();
}

pub export fn turbotoken_count_non_ascii_kernel_id() u32 {
    if (builtin.cpu.arch != .aarch64 or !aarch64.available()) {
        return 0;
    }
    return @intFromEnum(aarch64.selectedCountNonAsciiKernel());
}

pub export fn turbotoken_count_non_ascii_utf8(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }

    const in_slice = text[0..text_len];
    const count = if (builtin.cpu.arch == .aarch64 and aarch64.available())
        aarch64.countNonAscii(in_slice)
    else
        countNonAsciiScalar(in_slice);

    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_non_ascii_utf8_scalar(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }

    const count = countNonAsciiScalar(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_non_ascii_utf8_neon(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }
    if (builtin.cpu.arch != .aarch64 or !aarch64.available()) {
        return -1;
    }

    const count = aarch64.countNonAsciiNeon(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_non_ascii_utf8_dotprod(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }
    if (builtin.cpu.arch != .aarch64 or !aarch64.dotprodAvailable()) {
        return -1;
    }

    const count = aarch64.countNonAsciiDotProd(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_non_ascii_utf8_sme(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len == 0) {
        return 0;
    }
    if (text == null) {
        return -1;
    }
    if (builtin.cpu.arch != .aarch64 or !aarch64.smeAvailable()) {
        return -1;
    }

    const count = aarch64.countNonAsciiSme(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
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

pub export fn turbotoken_encode_bpe_batch_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    offsets: [*c]const u32,
    offsets_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
    out_token_offsets: [*c]u32,
    out_token_offsets_len: usize,
) isize {
    if (rank_bytes == null or offsets == null) {
        return -1;
    }
    if (text_len > 0 and text == null) {
        return -1;
    }
    if (offsets_len == 0) {
        return -1;
    }
    if (out_token_offsets != null and out_token_offsets_len < offsets_len) {
        return -1;
    }

    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    const offset_slice = offsets[0..offsets_len];

    if (offset_slice[0] != 0) {
        return -1;
    }
    var prev = offset_slice[0];
    for (offset_slice[1..]) |next| {
        if (next < prev or next > text_len) {
            return -1;
        }
        prev = next;
    }

    const segment_count = offsets_len - 1;
    if (out_token_offsets != null) {
        out_token_offsets[0] = 0;
    }
    if (segment_count == 0) {
        return 0;
    }

    const allocator = std.heap.page_allocator;
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();

    var total_tokens: usize = 0;
    for (0..segment_count) |idx| {
        const start = offset_slice[idx];
        const end = offset_slice[idx + 1];
        const segment = in_slice[start..end];

        if (out_tokens == null) {
            const counted = backend.count(allocator, segment, table) catch return -1;
            if (counted > std.math.maxInt(usize) - total_tokens) {
                return -1;
            }
            total_tokens += counted;
        } else {
            const tokens = backend.encode(allocator, segment, table) catch return -1;
            defer allocator.free(tokens);
            if (tokens.len > out_cap -| total_tokens) {
                return -1;
            }
            @memcpy(out_tokens[total_tokens .. total_tokens + tokens.len], tokens);
            total_tokens += tokens.len;
        }

        if (out_token_offsets != null) {
            if (total_tokens > std.math.maxInt(u32)) {
                return -1;
            }
            out_token_offsets[idx + 1] = @as(u32, @intCast(total_tokens));
        }
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
}

pub export fn turbotoken_encode_bpe_ranges_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    range_starts: [*c]const u32,
    range_ends: [*c]const u32,
    ranges_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
    out_token_offsets: [*c]u32,
    out_token_offsets_len: usize,
) isize {
    if (rank_bytes == null or range_starts == null or range_ends == null) {
        return -1;
    }
    if (text_len > 0 and text == null) {
        return -1;
    }
    if (out_token_offsets != null and out_token_offsets_len < ranges_len + 1) {
        return -1;
    }

    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    const starts = range_starts[0..ranges_len];
    const ends = range_ends[0..ranges_len];

    if (out_token_offsets != null) {
        out_token_offsets[0] = 0;
    }
    if (ranges_len == 0) {
        return 0;
    }

    const allocator = std.heap.page_allocator;
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();

    var total_tokens: usize = 0;
    for (0..ranges_len) |idx| {
        const start = starts[idx];
        const end = ends[idx];
        if (start > end or end > text_len) {
            return -1;
        }
        const segment = in_slice[start..end];

        if (out_tokens == null) {
            const counted = backend.count(allocator, segment, table) catch return -1;
            if (counted > std.math.maxInt(usize) - total_tokens) {
                return -1;
            }
            total_tokens += counted;
        } else {
            const tokens = backend.encode(allocator, segment, table) catch return -1;
            defer allocator.free(tokens);
            if (tokens.len > out_cap -| total_tokens) {
                return -1;
            }
            @memcpy(out_tokens[total_tokens .. total_tokens + tokens.len], tokens);
            total_tokens += tokens.len;
        }

        if (out_token_offsets != null) {
            if (total_tokens > std.math.maxInt(u32)) {
                return -1;
            }
            out_token_offsets[idx + 1] = @as(u32, @intCast(total_tokens));
        }
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
}

pub export fn turbotoken_encode_bpe_chunked_stitched_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    chunk_bytes: usize,
    overlap_bytes: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (rank_bytes == null) {
        return -1;
    }
    if (chunk_bytes == 0 or overlap_bytes == 0) {
        return -1;
    }
    if (text_len > 0 and text == null) {
        return -1;
    }

    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    if (in_slice.len == 0) {
        return 0;
    }

    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();
    const allocator = std.heap.page_allocator;

    const num_chunks = (in_slice.len + chunk_bytes - 1) / chunk_bytes;
    var total_tokens: usize = 0;

    for (0..num_chunks) |chunk_idx| {
        const start = chunk_idx * chunk_bytes;
        const end = @min(in_slice.len, start + chunk_bytes);
        const ext_start = start -| overlap_bytes;
        const ext_end = @min(in_slice.len, end + overlap_bytes);
        const ext = in_slice[ext_start..ext_end];

        const ext_tokens = backend.encode(allocator, ext, table) catch return -1;
        defer allocator.free(ext_tokens);

        var cursor: usize = 0;
        for (ext_tokens) |token| {
            const token_bytes = table.tokenForRank(token) orelse return -1;
            const token_len = token_bytes.len;
            if (token_len > ext.len -| cursor) {
                return -1;
            }

            const global_start = ext_start + cursor;
            const owner = @min(global_start / chunk_bytes, num_chunks - 1);
            if (owner == chunk_idx) {
                if (out_tokens != null) {
                    if (total_tokens >= out_cap) {
                        return -1;
                    }
                    out_tokens[total_tokens] = token;
                }
                total_tokens += 1;
            }
            cursor += token_len;
        }

        if (cursor != ext.len) {
            return -1;
        }
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
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

test "ascii letter/space pretokenizer export returns ranges" {
    const text = "hello  world";
    const needed = turbotoken_pretokenize_ascii_letter_space_ranges(text.ptr, text.len, null, null, 0);
    try std.testing.expectEqual(@as(isize, 3), needed);

    var starts: [3]u32 = undefined;
    var ends: [3]u32 = undefined;
    const written = turbotoken_pretokenize_ascii_letter_space_ranges(text.ptr, text.len, &starts, &ends, starts.len);
    try std.testing.expectEqual(@as(isize, 3), written);
    try std.testing.expectEqualSlices(u8, "hello", text[starts[0]..ends[0]]);
    try std.testing.expectEqualSlices(u8, " ", text[starts[1]..ends[1]]);
    try std.testing.expectEqualSlices(u8, " world", text[starts[2]..ends[2]]);
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

test "count non-ascii exports agree with scalar baseline" {
    const text = "a🚀b";
    const expected = countNonAsciiScalar(text);

    try std.testing.expectEqual(@as(isize, @intCast(expected)), turbotoken_count_non_ascii_utf8(text.ptr, text.len));
    try std.testing.expectEqual(@as(isize, @intCast(expected)), turbotoken_count_non_ascii_utf8_scalar(text.ptr, text.len));

    const feature_mask = turbotoken_arm64_feature_mask();
    const kernel_id = turbotoken_count_non_ascii_kernel_id();
    if (builtin.cpu.arch == .aarch64 and aarch64.available()) {
        try std.testing.expect((feature_mask & aarch64.FeatureBit.advsimd) != 0);
        try std.testing.expect(
            kernel_id == @intFromEnum(aarch64.CountKernel.neon) or
                kernel_id == @intFromEnum(aarch64.CountKernel.dotprod) or
                kernel_id == @intFromEnum(aarch64.CountKernel.sme),
        );
        try std.testing.expectEqual(@as(isize, @intCast(expected)), turbotoken_count_non_ascii_utf8_neon(text.ptr, text.len));
        const dotprod = turbotoken_count_non_ascii_utf8_dotprod(text.ptr, text.len);
        if (dotprod >= 0) {
            try std.testing.expectEqual(@as(isize, @intCast(expected)), dotprod);
        }
        const sme = turbotoken_count_non_ascii_utf8_sme(text.ptr, text.len);
        if (sme >= 0) {
            try std.testing.expectEqual(@as(isize, @intCast(expected)), sme);
        }
    } else {
        try std.testing.expectEqual(@as(u64, 0), feature_mask);
        try std.testing.expectEqual(@as(u32, 0), kernel_id);
        try std.testing.expectEqual(@as(isize, -1), turbotoken_count_non_ascii_utf8_neon(text.ptr, text.len));
        try std.testing.expectEqual(@as(isize, -1), turbotoken_count_non_ascii_utf8_dotprod(text.ptr, text.len));
        try std.testing.expectEqual(@as(isize, -1), turbotoken_count_non_ascii_utf8_sme(text.ptr, text.len));
    }
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

test "batch bpe encode from ranks returns flattened tokens and token offsets" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const text = "abbabb";
    const offsets = [_]u32{ 0, 3, 6 };

    var token_offsets: [3]u32 = undefined;
    const needed = turbotoken_encode_bpe_batch_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &offsets,
        offsets.len,
        null,
        0,
        &token_offsets,
        token_offsets.len,
    );
    try std.testing.expectEqual(@as(isize, 4), needed);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 4 }, &token_offsets);

    var tokens: [4]u32 = undefined;
    const written = turbotoken_encode_bpe_batch_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &offsets,
        offsets.len,
        &tokens,
        tokens.len,
        &token_offsets,
        token_offsets.len,
    );
    try std.testing.expectEqual(@as(isize, 4), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1, 2, 1 }, &tokens);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 4 }, &token_offsets);
}

test "range bpe encode from ranks handles overlapping windows" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const text = "abbabb";
    const starts = [_]u32{ 0, 0 };
    const ends = [_]u32{ 3, 3 };

    var token_offsets: [3]u32 = undefined;
    var tokens: [4]u32 = undefined;
    const written = turbotoken_encode_bpe_ranges_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &starts,
        &ends,
        starts.len,
        &tokens,
        tokens.len,
        &token_offsets,
        token_offsets.len,
    );
    try std.testing.expectEqual(@as(isize, 4), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1, 2, 1 }, &tokens);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 4 }, &token_offsets);
}

test "chunked stitched bpe export matches direct encode on byte-level ranks" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\Yw== 2
        \\
    ;
    const text = "abcabcabcabc";

    var direct_tokens: [text.len]u32 = undefined;
    const direct_written = turbotoken_encode_bpe_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &direct_tokens,
        direct_tokens.len,
    );
    try std.testing.expectEqual(@as(isize, text.len), direct_written);

    var stitched_tokens: [16]u32 = undefined;
    const stitched_written = turbotoken_encode_bpe_chunked_stitched_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        4,
        4,
        &stitched_tokens,
        stitched_tokens.len,
    );
    try std.testing.expectEqual(@as(isize, text.len), stitched_written);
    try std.testing.expectEqualSlices(u32, &direct_tokens, stitched_tokens[0..text.len]);
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
