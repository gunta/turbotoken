const std = @import("std");

const binary_magic = "TTKRBIN1";
const binary_version: u32 = 1;
const binary_missing_len: u32 = std.math.maxInt(u32);

pub const RankEntry = struct {
    token: []u8,
    rank: u32,
};

pub const RankTable = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(RankEntry) = .{},
    by_token: std.StringHashMapUnmanaged(u32) = .{},
    by_rank: std.AutoHashMapUnmanaged(u32, []u8) = .{},
    by_rank_dense: std.ArrayListUnmanaged(?[]u8) = .{},

    pub fn init(allocator: std.mem.Allocator) RankTable {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RankTable) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.token);
        }
        self.entries.deinit(self.allocator);
        self.by_token.deinit(self.allocator);
        self.by_rank.deinit(self.allocator);
        self.by_rank_dense.deinit(self.allocator);
    }

    pub fn len(self: *const RankTable) usize {
        return self.entries.items.len;
    }

    pub fn get(self: *const RankTable, token: []const u8) ?u32 {
        return self.by_token.get(token);
    }

    pub fn tokenForRank(self: *const RankTable, rank: u32) ?[]const u8 {
        const idx: usize = @intCast(rank);
        if (idx < self.by_rank_dense.items.len) {
            if (self.by_rank_dense.items[idx]) |token| {
                return token;
            }
        }
        return self.by_rank.get(rank);
    }

    pub fn maxRankPlusOne(self: *const RankTable) usize {
        var idx = self.by_rank_dense.items.len;
        while (idx > 0) : (idx -= 1) {
            if (self.by_rank_dense.items[idx - 1] != null) {
                return idx;
            }
        }
        return 0;
    }

    fn addOwned(self: *RankTable, token: []u8, rank: u32) !void {
        if (self.by_token.contains(token)) {
            return error.DuplicateToken;
        }
        if (self.by_rank.contains(rank)) {
            return error.DuplicateRank;
        }

        const rank_idx: usize = @intCast(rank);
        if (rank_idx >= self.by_rank_dense.items.len) {
            const grow_by = (rank_idx + 1) - self.by_rank_dense.items.len;
            try self.by_rank_dense.ensureUnusedCapacity(self.allocator, grow_by);
            var idx = self.by_rank_dense.items.len;
            while (idx <= rank_idx) : (idx += 1) {
                self.by_rank_dense.appendAssumeCapacity(null);
            }
        }
        if (self.by_rank_dense.items[rank_idx] != null) {
            return error.DuplicateRank;
        }

        try self.by_token.putNoClobber(self.allocator, token, rank);
        errdefer _ = self.by_token.remove(token);
        try self.by_rank.putNoClobber(self.allocator, rank, token);
        errdefer _ = self.by_rank.remove(rank);
        self.by_rank_dense.items[rank_idx] = token;
        errdefer self.by_rank_dense.items[rank_idx] = null;

        try self.entries.append(self.allocator, .{
            .token = token,
            .rank = rank,
        });
    }
};

pub fn loadFromBytes(allocator: std.mem.Allocator, payload: []const u8) !RankTable {
    if (std.mem.startsWith(u8, payload, binary_magic)) {
        return loadFromBinaryPayload(allocator, payload);
    }

    var table = RankTable.init(allocator);
    errdefer table.deinit();

    const stats = try scanRankPayloadStats(payload);
    if (stats.line_count > 0) {
        try table.entries.ensureTotalCapacity(allocator, stats.line_count);
        if (stats.line_count > std.math.maxInt(u32)) {
            return error.InvalidLine;
        }
        const map_capacity: u32 = @intCast(stats.line_count);
        try table.by_token.ensureTotalCapacity(allocator, map_capacity);
        try table.by_rank.ensureTotalCapacity(allocator, map_capacity);

        const dense_len = @as(usize, stats.max_rank) + 1;
        try table.by_rank_dense.ensureTotalCapacity(allocator, dense_len);
        var idx: usize = 0;
        while (idx < dense_len) : (idx += 1) {
            table.by_rank_dense.appendAssumeCapacity(null);
        }
    }

    var line_iter = std.mem.splitScalar(u8, payload, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            continue;
        }

        const sep = std.mem.indexOfAny(u8, line, " \t") orelse return error.InvalidLine;
        const token_b64 = std.mem.trim(u8, line[0..sep], " \t");
        const rank_text = std.mem.trim(u8, line[sep + 1 ..], " \t");
        if (token_b64.len == 0 or rank_text.len == 0) {
            return error.InvalidLine;
        }

        const rank = std.fmt.parseInt(u32, rank_text, 10) catch return error.InvalidRank;

        const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(token_b64) catch return error.InvalidBase64;
        const token_bytes = try allocator.alloc(u8, decoded_len);
        errdefer allocator.free(token_bytes);

        _ = std.base64.standard.Decoder.decode(token_bytes, token_b64) catch return error.InvalidBase64;
        try table.addOwned(token_bytes, rank);
    }

    return table;
}

fn readU32Le(payload: []const u8, offset: *usize) !u32 {
    if (payload.len < offset.* + 4) {
        return error.InvalidBinary;
    }
    const value = std.mem.readInt(u32, payload[offset.* .. offset.* + 4][0..4], .little);
    offset.* += 4;
    return value;
}

fn readU64Le(payload: []const u8, offset: *usize) !u64 {
    if (payload.len < offset.* + 8) {
        return error.InvalidBinary;
    }
    const value = std.mem.readInt(u64, payload[offset.* .. offset.* + 8][0..8], .little);
    offset.* += 8;
    return value;
}

fn loadFromBinaryPayload(allocator: std.mem.Allocator, payload: []const u8) !RankTable {
    var offset: usize = 0;
    if (payload.len < binary_magic.len) {
        return error.InvalidBinary;
    }
    if (!std.mem.eql(u8, payload[0..binary_magic.len], binary_magic)) {
        return error.InvalidBinary;
    }
    offset += binary_magic.len;

    const version = try readU32Le(payload, &offset);
    const flags = try readU32Le(payload, &offset);
    _ = try readU64Le(payload, &offset); // source file size (informational)
    _ = try readU64Le(payload, &offset); // source file mtime ns (informational)
    const entry_count_u32 = try readU32Le(payload, &offset);
    const max_rank_plus_one_u32 = try readU32Le(payload, &offset);

    if (version != binary_version or flags != 0) {
        return error.InvalidBinary;
    }
    if (entry_count_u32 > max_rank_plus_one_u32) {
        return error.InvalidBinary;
    }

    const entry_count: usize = @intCast(entry_count_u32);
    const max_rank_plus_one: usize = @intCast(max_rank_plus_one_u32);

    var table = RankTable.init(allocator);
    errdefer table.deinit();

    if (entry_count > 0) {
        try table.entries.ensureTotalCapacity(allocator, entry_count);
        try table.by_token.ensureTotalCapacity(allocator, entry_count_u32);

        try table.by_rank_dense.ensureTotalCapacity(allocator, max_rank_plus_one);
        var idx: usize = 0;
        while (idx < max_rank_plus_one) : (idx += 1) {
            table.by_rank_dense.appendAssumeCapacity(null);
        }
    }

    var parsed_entries: usize = 0;
    for (0..max_rank_plus_one) |rank_idx| {
        const token_len_u32 = try readU32Le(payload, &offset);
        if (token_len_u32 == binary_missing_len) {
            continue;
        }

        const token_len: usize = @intCast(token_len_u32);
        if (payload.len < offset + token_len) {
            return error.InvalidBinary;
        }

        const token_copy = try allocator.alloc(u8, token_len);
        const token_src = payload[offset .. offset + token_len];
        @memcpy(token_copy, token_src);
        offset += token_len;

        const rank: u32 = @intCast(rank_idx);
        try table.by_token.putNoClobber(allocator, token_copy, rank);
        table.by_rank_dense.items[rank_idx] = token_copy;
        try table.entries.append(allocator, .{
            .token = token_copy,
            .rank = rank,
        });
        parsed_entries += 1;
    }

    if (parsed_entries != entry_count) {
        return error.InvalidBinary;
    }
    if (offset != payload.len) {
        return error.InvalidBinary;
    }

    return table;
}

const RankPayloadStats = struct {
    line_count: usize = 0,
    max_rank: u32 = 0,
};

fn scanRankPayloadStats(payload: []const u8) !RankPayloadStats {
    var stats: RankPayloadStats = .{};
    var line_iter = std.mem.splitScalar(u8, payload, '\n');
    while (line_iter.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) {
            continue;
        }

        const sep = std.mem.indexOfAny(u8, line, " \t") orelse return error.InvalidLine;
        const token_b64 = std.mem.trim(u8, line[0..sep], " \t");
        const rank_text = std.mem.trim(u8, line[sep + 1 ..], " \t");
        if (token_b64.len == 0 or rank_text.len == 0) {
            return error.InvalidLine;
        }

        const rank = std.fmt.parseInt(u32, rank_text, 10) catch return error.InvalidRank;
        if (stats.line_count == 0 or rank > stats.max_rank) {
            stats.max_rank = rank;
        }
        stats.line_count += 1;
    }
    return stats;
}

test "loadFromBytes parses valid rank data" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 1
        \\Yg== 2
        \\
    ;

    var table = try loadFromBytes(allocator, payload);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.len());
    try std.testing.expectEqual(@as(usize, 3), table.maxRankPlusOne());
    try std.testing.expectEqual(@as(?u32, 1), table.get("a"));
    try std.testing.expectEqual(@as(?u32, 2), table.get("b"));
    try std.testing.expectEqualStrings("a", table.tokenForRank(1).?);
    try std.testing.expect(table.tokenForRank(999) == null);
}

test "loadFromBytes supports sparse high rank lookups" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1024
        \\
    ;

    var table = try loadFromBytes(allocator, payload);
    defer table.deinit();

    try std.testing.expectEqualStrings("a", table.tokenForRank(0).?);
    try std.testing.expectEqualStrings("b", table.tokenForRank(1024).?);
    try std.testing.expect(table.tokenForRank(1023) == null);
    try std.testing.expectEqual(@as(usize, 1025), table.maxRankPlusOne());
}

test "loadFromBytes rejects malformed lines" {
    const allocator = std.testing.allocator;
    const payload = "not-a-valid-line";
    try std.testing.expectError(error.InvalidLine, loadFromBytes(allocator, payload));
}

test "loadFromBytes rejects duplicate tokens" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 1
        \\YQ== 2
        \\
    ;
    try std.testing.expectError(error.DuplicateToken, loadFromBytes(allocator, payload));
}

test "loadFromBytes rejects duplicate ranks" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 1
        \\Yg== 1
        \\
    ;
    try std.testing.expectError(error.DuplicateRank, loadFromBytes(allocator, payload));
}

test "loadFromBytes rejects invalid base64 and invalid rank" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidBase64, loadFromBytes(allocator, "%%% 1\n"));
    try std.testing.expectError(error.InvalidRank, loadFromBytes(allocator, "YQ== no-int\n"));
}

test "loadFromBytes supports native binary payload format" {
    const allocator = std.testing.allocator;

    var payload = std.ArrayListUnmanaged(u8){};
    defer payload.deinit(allocator);

    try payload.appendSlice(allocator, binary_magic);

    var u32_buf: [4]u8 = undefined;
    var u64_buf: [8]u8 = undefined;

    std.mem.writeInt(u32, &u32_buf, binary_version, .little);
    try payload.appendSlice(allocator, &u32_buf);
    std.mem.writeInt(u32, &u32_buf, 0, .little); // flags
    try payload.appendSlice(allocator, &u32_buf);
    std.mem.writeInt(u64, &u64_buf, 16, .little); // source size
    try payload.appendSlice(allocator, &u64_buf);
    std.mem.writeInt(u64, &u64_buf, 0, .little); // source mtime
    try payload.appendSlice(allocator, &u64_buf);
    std.mem.writeInt(u32, &u32_buf, 2, .little); // entry count
    try payload.appendSlice(allocator, &u32_buf);
    std.mem.writeInt(u32, &u32_buf, 3, .little); // max_rank_plus_one
    try payload.appendSlice(allocator, &u32_buf);

    // rank 0 -> "a"
    std.mem.writeInt(u32, &u32_buf, 1, .little);
    try payload.appendSlice(allocator, &u32_buf);
    try payload.append(allocator, 'a');
    // rank 1 -> missing
    std.mem.writeInt(u32, &u32_buf, binary_missing_len, .little);
    try payload.appendSlice(allocator, &u32_buf);
    // rank 2 -> "b"
    std.mem.writeInt(u32, &u32_buf, 1, .little);
    try payload.appendSlice(allocator, &u32_buf);
    try payload.append(allocator, 'b');

    var table = try loadFromBytes(allocator, payload.items);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 2), table.len());
    try std.testing.expectEqual(@as(usize, 3), table.maxRankPlusOne());
    try std.testing.expectEqual(@as(?u32, 0), table.get("a"));
    try std.testing.expectEqual(@as(?u32, 2), table.get("b"));
    try std.testing.expect(table.tokenForRank(1) == null);
    try std.testing.expectEqualStrings("a", table.tokenForRank(0).?);
    try std.testing.expectEqualStrings("b", table.tokenForRank(2).?);
}
