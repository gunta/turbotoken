const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const pair_cache = @import("pair_cache.zig");
const rank_loader = @import("rank_loader.zig");

pub const Encoder = struct {
    const Node = struct {
        start: usize,
        end: usize,
        token: u32,
        prev: ?usize,
        next: ?usize,
        alive: bool,
        version: u32,
    };

    const Candidate = struct {
        left: usize,
        right: usize,
        rank: u32,
        left_version: u32,
        right_version: u32,
    };

    const CandidateQueue = std.PriorityQueue(Candidate, void, compareCandidate);
    const cache_miss = std.math.maxInt(u32);
    const MergeResult = struct {
        nodes: []Node,
        head_idx: usize,
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
        nodes: []Node,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
        left_idx: usize,
    ) !void {
        if (left_idx >= nodes.len) {
            return;
        }

        const left = nodes[left_idx];
        if (!left.alive) {
            return;
        }

        const right_idx = left.next orelse return;
        const right = nodes[right_idx];
        if (!right.alive) {
            return;
        }

        const rank = try pairRank(allocator, table, cache, scratch, left.token, right.token) orelse return;

        try queue.add(.{
            .left = left_idx,
            .right = right_idx,
            .rank = rank,
            .left_version = left.version,
            .right_version = right.version,
        });
    }

    fn buildMergedNodes(
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) !MergeResult {
        const nodes = try allocator.alloc(Node, text.len);
        errdefer allocator.free(nodes);

        for (text, 0..) |_, idx| {
            const byte_token = table.get(text[idx .. idx + 1]) orelse return error.UnknownToken;
            nodes[idx] = .{
                .start = idx,
                .end = idx + 1,
                .token = byte_token,
                .prev = if (idx == 0) null else idx - 1,
                .next = if (idx + 1 < text.len) idx + 1 else null,
                .alive = true,
                .version = 0,
            };
        }

        var cache = pair_cache.PairCache.init();
        _ = cache.populateFromKnownSeedSets(table);
        var scratch = std.ArrayListUnmanaged(u8){};
        defer scratch.deinit(allocator);

        var queue = CandidateQueue.init(allocator, {});
        defer queue.deinit();

        if (nodes.len > 1) {
            try queue.ensureTotalCapacity(nodes.len - 1);
            for (0..nodes.len - 1) |idx| {
                try enqueueCandidate(allocator, &queue, nodes, table, &cache, &scratch, idx);
            }
        }

        while (queue.removeOrNull()) |candidate| {
            if (candidate.left >= nodes.len or candidate.right >= nodes.len) {
                continue;
            }

            var left = &nodes[candidate.left];
            if (!left.alive or left.version != candidate.left_version) {
                continue;
            }

            const actual_right_idx = left.next orelse continue;
            if (actual_right_idx != candidate.right) {
                continue;
            }

            var right = &nodes[actual_right_idx];
            if (!right.alive or right.version != candidate.right_version) {
                continue;
            }

            const current_rank = try pairRank(allocator, table, &cache, &scratch, left.token, right.token) orelse continue;
            if (current_rank != candidate.rank) {
                continue;
            }

            left.end = right.end;
            left.token = current_rank;
            left.next = right.next;
            left.version +%= 1;

            if (right.next) |next_idx| {
                nodes[next_idx].prev = candidate.left;
                nodes[next_idx].version +%= 1;
            }

            right.alive = false;
            right.prev = null;
            right.next = null;
            right.version +%= 1;

            if (left.prev) |prev_idx| {
                try enqueueCandidate(allocator, &queue, nodes, table, &cache, &scratch, prev_idx);
            }
            try enqueueCandidate(allocator, &queue, nodes, table, &cache, &scratch, candidate.left);
        }

        var head_idx: ?usize = null;
        for (nodes, 0..) |node, idx| {
            if (node.alive and node.prev == null) {
                head_idx = idx;
                break;
            }
        }

        return .{
            .nodes = nodes,
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

        const merged = try buildMergedNodes(allocator, text, table);
        defer allocator.free(merged.nodes);
        const nodes = merged.nodes;

        var out = std.ArrayListUnmanaged(u32){};
        errdefer out.deinit(allocator);

        var cursor: ?usize = merged.head_idx;
        while (cursor) |idx| : (cursor = nodes[idx].next) {
            if (!nodes[idx].alive) {
                return error.InvalidTokenizerState;
            }
            try out.append(allocator, nodes[idx].token);
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

        const merged = try buildMergedNodes(allocator, text, table);
        defer allocator.free(merged.nodes);

        var count: usize = 0;
        var cursor: ?usize = merged.head_idx;
        while (cursor) |idx| : (cursor = merged.nodes[idx].next) {
            if (!merged.nodes[idx].alive) {
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
