const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const pair_cache = @import("pair_cache.zig");
const rank_loader = @import("rank_loader.zig");

pub const Encoder = struct {
    const NodeIndex = u32;
    const null_index = std.math.maxInt(NodeIndex);
    const dead_index: NodeIndex = std.math.maxInt(NodeIndex) - 1;

    const NodeArena = struct {
        start: []u32,
        end: []u32,
        token: []u32,
        prev: []NodeIndex,
        next: []NodeIndex,
        version: []u32,

        fn init(allocator: std.mem.Allocator, node_count: usize) !NodeArena {
            var arena: NodeArena = undefined;
            arena.start = try allocator.alloc(u32, node_count);
            errdefer allocator.free(arena.start);
            arena.end = try allocator.alloc(u32, node_count);
            errdefer allocator.free(arena.end);
            arena.token = try allocator.alloc(u32, node_count);
            errdefer allocator.free(arena.token);
            arena.prev = try allocator.alloc(NodeIndex, node_count);
            errdefer allocator.free(arena.prev);
            arena.next = try allocator.alloc(NodeIndex, node_count);
            errdefer allocator.free(arena.next);
            arena.version = try allocator.alloc(u32, node_count);
            errdefer allocator.free(arena.version);
            return arena;
        }

        fn deinit(self: *NodeArena, allocator: std.mem.Allocator) void {
            allocator.free(self.start);
            allocator.free(self.end);
            allocator.free(self.token);
            allocator.free(self.prev);
            allocator.free(self.next);
            allocator.free(self.version);
        }

        fn isAlive(self: *const NodeArena, idx: usize) bool {
            return self.next[idx] != dead_index;
        }
    };

    const Candidate = struct {
        rank: u32,
        left: NodeIndex,
        right: NodeIndex,
        left_version: u32,
        right_version: u32,
    };

    const CandidateQueue = std.PriorityQueue(Candidate, void, compareCandidate);
    const cache_miss = std.math.maxInt(u32);
    const MergeResult = struct {
        arena: NodeArena,
        head_idx: NodeIndex,
    };

    fn compareCandidate(_: void, a: Candidate, b: Candidate) std.math.Order {
        const rank_order = std.math.order(a.rank, b.rank);
        if (rank_order != .eq) {
            return rank_order;
        }

        const left_order = std.math.order(a.left, b.left);
        if (left_order != .eq) {
            return left_order;
        }
        return std.math.order(a.right, b.right);
    }

    fn pairRank(
        allocator: std.mem.Allocator,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
        left_token: u32,
        right_token: u32,
    ) !?u32 {
        if (cache.get(left_token, right_token)) |cached| {
            return if (cached == cache_miss) null else cached;
        }

        const left_bytes = table.tokenForRank(left_token) orelse return error.UnknownTokenRank;
        const right_bytes = table.tokenForRank(right_token) orelse return error.UnknownTokenRank;

        const merged_len = left_bytes.len + right_bytes.len;
        const resolved_rank = blk: {
            if (merged_len <= 128) {
                var merged_stack: [128]u8 = undefined;
                @memcpy(merged_stack[0..left_bytes.len], left_bytes);
                @memcpy(merged_stack[left_bytes.len..merged_len], right_bytes);
                break :blk table.get(merged_stack[0..merged_len]);
            }

            scratch.clearRetainingCapacity();
            try scratch.ensureTotalCapacity(allocator, merged_len);
            scratch.items.len = merged_len;
            @memcpy(scratch.items[0..left_bytes.len], left_bytes);
            @memcpy(scratch.items[left_bytes.len..merged_len], right_bytes);
            break :blk table.get(scratch.items[0..merged_len]);
        };
        _ = cache.put(left_token, right_token, resolved_rank orelse cache_miss);
        return resolved_rank;
    }

    fn enqueueCandidate(
        allocator: std.mem.Allocator,
        queue: *CandidateQueue,
        arena: *const NodeArena,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
        left_idx: usize,
    ) !void {
        if (left_idx >= arena.token.len) {
            return;
        }

        if (!arena.isAlive(left_idx)) {
            return;
        }

        const right_idx = arena.next[left_idx];
        if (right_idx == null_index or right_idx == dead_index) {
            return;
        }

        const right_usize = @as(usize, right_idx);
        if (!arena.isAlive(right_usize)) {
            return;
        }

        const rank = try pairRank(allocator, table, cache, scratch, arena.token[left_idx], arena.token[right_usize]) orelse return;

        try queue.add(.{
            .left = @as(NodeIndex, @intCast(left_idx)),
            .right = right_idx,
            .rank = rank,
            .left_version = arena.version[left_idx],
            .right_version = arena.version[right_usize],
        });
    }

    fn buildMergedNodes(
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) !MergeResult {
        if (text.len > @as(usize, dead_index)) {
            return error.InputTooLarge;
        }

        var arena = try NodeArena.init(allocator, text.len);
        errdefer arena.deinit(allocator);

        for (text, 0..) |_, idx| {
            const byte_token = table.get(text[idx .. idx + 1]) orelse return error.UnknownToken;
            const idx_u32 = @as(u32, @intCast(idx));
            arena.start[idx] = idx_u32;
            arena.end[idx] = idx_u32 + 1;
            arena.token[idx] = byte_token;
            arena.prev[idx] = if (idx == 0) null_index else @as(NodeIndex, @intCast(idx - 1));
            arena.next[idx] = if (idx + 1 < text.len) @as(NodeIndex, @intCast(idx + 1)) else null_index;
            arena.version[idx] = 0;
        }

        var cache = pair_cache.PairCache.init();
        _ = cache.populateFromKnownSeedSets(table);
        var scratch = std.ArrayListUnmanaged(u8){};
        defer scratch.deinit(allocator);

        var queue = CandidateQueue.init(allocator, {});
        defer queue.deinit();

        if (arena.token.len > 1) {
            try queue.ensureTotalCapacity(arena.token.len - 1);
            for (0..arena.token.len - 1) |idx| {
                try enqueueCandidate(allocator, &queue, &arena, table, &cache, &scratch, idx);
            }
        }

        while (queue.removeOrNull()) |candidate| {
            const left_idx = @as(usize, candidate.left);
            const right_idx = @as(usize, candidate.right);
            if (left_idx >= arena.token.len or right_idx >= arena.token.len) {
                continue;
            }

            if (!arena.isAlive(left_idx) or arena.version[left_idx] != candidate.left_version) {
                continue;
            }

            const actual_right_idx = arena.next[left_idx];
            if (actual_right_idx == null_index or actual_right_idx == dead_index) {
                continue;
            }
            if (actual_right_idx != candidate.right) {
                continue;
            }

            const actual_right_usize = @as(usize, actual_right_idx);
            if (!arena.isAlive(actual_right_usize) or arena.version[actual_right_usize] != candidate.right_version) {
                continue;
            }

            const prev_idx = arena.prev[left_idx];
            const next_next_idx = arena.next[actual_right_usize];
            if (prev_idx != null_index and prev_idx != dead_index) {
                const prev_usize = @as(usize, prev_idx);
                const prev_rank_slot = cache.slotIndexFor(arena.token[prev_usize], candidate.rank);
                @prefetch(&cache.entries[prev_rank_slot], .{ .rw = .read, .locality = 3 });
            }
            if (next_next_idx != null_index and next_next_idx != dead_index) {
                const next_next_usize = @as(usize, next_next_idx);
                const next_rank_slot = cache.slotIndexFor(candidate.rank, arena.token[next_next_usize]);
                @prefetch(&cache.entries[next_rank_slot], .{ .rw = .read, .locality = 3 });
            }

            arena.end[left_idx] = arena.end[actual_right_usize];
            arena.token[left_idx] = candidate.rank;
            arena.next[left_idx] = next_next_idx;
            arena.version[left_idx] +%= 1;

            if (next_next_idx != null_index and next_next_idx != dead_index) {
                const next_idx = @as(usize, next_next_idx);
                arena.prev[next_idx] = candidate.left;
                arena.version[next_idx] +%= 1;
            }

            arena.prev[actual_right_usize] = dead_index;
            arena.next[actual_right_usize] = dead_index;
            arena.version[actual_right_usize] +%= 1;

            if (prev_idx != null_index and prev_idx != dead_index) {
                try enqueueCandidate(allocator, &queue, &arena, table, &cache, &scratch, @as(usize, prev_idx));
            }
            try enqueueCandidate(allocator, &queue, &arena, table, &cache, &scratch, left_idx);
        }

        var head_idx: ?NodeIndex = null;
        for (0..arena.token.len) |idx| {
            if (arena.isAlive(idx) and arena.prev[idx] == null_index) {
                head_idx = @as(NodeIndex, @intCast(idx));
                break;
            }
        }

        return .{
            .arena = arena,
            .head_idx = head_idx orelse return error.InvalidTokenizerState,
        };
    }

    pub fn init() Encoder {
        return .{};
    }

    pub fn encode(self: *const Encoder, allocator: std.mem.Allocator, text: []const u8) ![]u32 {
        _ = self;
        var out = try allocator.alloc(u32, text.len);

        if (builtin.cpu.arch == .aarch64 and aarch64.available() and text.len >= 16) {
            aarch64.encodeU8ToU32(text, out);
            return out;
        }

        for (text, 0..) |byte, idx| {
            out[idx] = byte;
        }
        return out;
    }

    pub fn encodeWithRanks(
        self: *const Encoder,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) ![]u32 {
        _ = self;

        if (text.len == 0) {
            return allocator.alloc(u32, 0);
        }

        var merged = try buildMergedNodes(allocator, text, table);
        defer merged.arena.deinit(allocator);
        const arena = &merged.arena;

        var out = std.ArrayListUnmanaged(u32){};
        errdefer out.deinit(allocator);

        var cursor = merged.head_idx;
        while (cursor != null_index) : (cursor = arena.next[@as(usize, cursor)]) {
            if (cursor == dead_index) {
                return error.InvalidTokenizerState;
            }
            const idx = @as(usize, cursor);
            if (!arena.isAlive(idx)) {
                return error.InvalidTokenizerState;
            }
            try out.append(allocator, arena.token[idx]);
        }

        return out.toOwnedSlice(allocator);
    }

    pub fn countWithRanks(
        self: *const Encoder,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) !usize {
        _ = self;

        if (text.len == 0) {
            return 0;
        }

        var merged = try buildMergedNodes(allocator, text, table);
        defer merged.arena.deinit(allocator);
        const arena = &merged.arena;

        var count: usize = 0;
        var cursor = merged.head_idx;
        while (cursor != null_index) : (cursor = arena.next[@as(usize, cursor)]) {
            if (cursor == dead_index) {
                return error.InvalidTokenizerState;
            }
            const idx = @as(usize, cursor);
            if (!arena.isAlive(idx)) {
                return error.InvalidTokenizerState;
            }
            count += 1;
        }

        return count;
    }
};

test "encodeWithRanks merges lowest-rank adjacent pairs first" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\Yw== 2
        \\YWI= 3
        \\YmI= 4
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const enc = Encoder.init();

    const tokens_ab = try enc.encodeWithRanks(allocator, "ab", &table);
    defer allocator.free(tokens_ab);
    try std.testing.expectEqualSlices(u32, &[_]u32{3}, tokens_ab);

    const tokens_abb = try enc.encodeWithRanks(allocator, "abb", &table);
    defer allocator.free(tokens_abb);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 3, 1 }, tokens_abb);

    const tokens_abc = try enc.encodeWithRanks(allocator, "abc", &table);
    defer allocator.free(tokens_abc);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 3, 2 }, tokens_abc);
}

test "encodeWithRanks handles stale queue candidates across merges" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\Yw== 2
        \\ZA== 3
        \\YWI= 4
        \\YmM= 5
        \\Y2Q= 6
        \\YWJj 7
        \\YmNk 8
        \\YWJjZA== 9
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const enc = Encoder.init();
    const tokens = try enc.encodeWithRanks(allocator, "abcd", &table);
    defer allocator.free(tokens);
    try std.testing.expectEqualSlices(u32, &[_]u32{9}, tokens);
}

test "encodeWithRanks errors when token is missing from rank table" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const enc = Encoder.init();
    try std.testing.expectError(error.UnknownToken, enc.encodeWithRanks(allocator, "ab", &table));
}

test "countWithRanks counts final tokenized segments without output allocation" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\Yw== 2
        \\YWI= 3
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    const enc = Encoder.init();
    try std.testing.expectEqual(@as(usize, 2), try enc.countWithRanks(allocator, "abc", &table));
}
