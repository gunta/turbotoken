const std = @import("std");

pub const RankEntry = struct {
    token: []u8,
    rank: u32,
};

pub const RankTable = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(RankEntry) = .{},
    by_token: std.StringHashMapUnmanaged(u32) = .{},
    by_rank: std.AutoHashMapUnmanaged(u32, []u8) = .{},

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
    }

    pub fn len(self: *const RankTable) usize {
        return self.entries.items.len;
    }

    pub fn get(self: *const RankTable, token: []const u8) ?u32 {
        return self.by_token.get(token);
    }

    pub fn tokenForRank(self: *const RankTable, rank: u32) ?[]const u8 {
        return self.by_rank.get(rank);
    }

    fn addOwned(self: *RankTable, token: []u8, rank: u32) !void {
        if (self.by_token.contains(token)) {
            return error.DuplicateToken;
        }
        if (self.by_rank.contains(rank)) {
            return error.DuplicateRank;
        }

        try self.by_token.putNoClobber(self.allocator, token, rank);
        errdefer _ = self.by_token.remove(token);
        try self.by_rank.putNoClobber(self.allocator, rank, token);
        errdefer _ = self.by_rank.remove(rank);

        try self.entries.append(self.allocator, .{
            .token = token,
            .rank = rank,
        });
    }
};

pub fn loadFromBytes(allocator: std.mem.Allocator, payload: []const u8) !RankTable {
    var table = RankTable.init(allocator);
    errdefer table.deinit();

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
    try std.testing.expectEqual(@as(?u32, 1), table.get("a"));
    try std.testing.expectEqual(@as(?u32, 2), table.get("b"));
    try std.testing.expectEqualStrings("a", table.tokenForRank(1).?);
    try std.testing.expect(table.tokenForRank(999) == null);
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
