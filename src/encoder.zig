const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const x86_64 = @import("arch/x86_64.zig");
const wasm_arch = @import("arch/wasm.zig");
const pair_cache = @import("pair_cache.zig");
const rank_loader = @import("rank_loader.zig");

pub const Encoder = struct {
    const NodeIndex = u32;
    const null_index = std.math.maxInt(NodeIndex);
    const dead_index: NodeIndex = std.math.maxInt(NodeIndex) - 1;
    const CandidateIndex = u32;
    const invalid_candidate = std.math.maxInt(CandidateIndex);
    const candidate_bucket_count: usize = 32_768;
    const max_full_bucket_count: usize = 1_048_576;

    const QueueMode = enum {
        hybrid,
        full_bucket,
    };

    var selected_queue_mode: QueueMode = .full_bucket;
    var queue_mode_once = std.once(initQueueMode);

    const NodeArena = struct {
        backing: []align(@alignOf(u32)) u8,
        start: []u32,
        end: []u32,
        token: []u32,
        prev: []NodeIndex,
        next: []NodeIndex,
        version: []u32,

        fn init(allocator: std.mem.Allocator, node_count: usize) !NodeArena {
            const elem_size = @sizeOf(u32) * node_count;
            const total_size = elem_size * 6;
            const backing = try allocator.alignedAlloc(u8, .fromByteUnits(@alignOf(u32)), total_size);

            var offset: usize = 0;
            const start_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const start_slice = std.mem.bytesAsSlice(u32, start_bytes);
            offset += elem_size;
            const end_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const end_slice = std.mem.bytesAsSlice(u32, end_bytes);
            offset += elem_size;
            const token_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const token_slice = std.mem.bytesAsSlice(u32, token_bytes);
            offset += elem_size;
            const prev_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const prev_slice = std.mem.bytesAsSlice(NodeIndex, prev_bytes);
            offset += elem_size;
            const next_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const next_slice = std.mem.bytesAsSlice(NodeIndex, next_bytes);
            offset += elem_size;
            const version_bytes: []align(@alignOf(u32)) u8 = @alignCast(backing[offset .. offset + elem_size]);
            const version_slice = std.mem.bytesAsSlice(u32, version_bytes);

            return .{
                .backing = backing,
                .start = start_slice,
                .end = end_slice,
                .token = token_slice,
                .prev = prev_slice,
                .next = next_slice,
                .version = version_slice,
            };
        }

        fn deinit(self: *NodeArena, allocator: std.mem.Allocator) void {
            allocator.free(self.backing);
        }

        fn isAlive(self: *const NodeArena, idx: usize) bool {
            return self.next[idx] != dead_index;
        }
    };

    const Candidate = struct {
        rank: u32,
        left: NodeIndex,
        left_version: u32,
        right_version: u32,
    };

    const CandidatePool = struct {
        rank: std.ArrayListUnmanaged(u32) = .{},
        left: std.ArrayListUnmanaged(NodeIndex) = .{},
        left_version: std.ArrayListUnmanaged(u32) = .{},
        right_version: std.ArrayListUnmanaged(u32) = .{},
        next: std.ArrayListUnmanaged(CandidateIndex) = .{},
        free_head: CandidateIndex = invalid_candidate,

        fn deinit(self: *CandidatePool, allocator: std.mem.Allocator) void {
            self.rank.deinit(allocator);
            self.left.deinit(allocator);
            self.left_version.deinit(allocator);
            self.right_version.deinit(allocator);
            self.next.deinit(allocator);
        }

        fn ensureTotalCapacity(self: *CandidatePool, allocator: std.mem.Allocator, capacity: usize) !void {
            try self.rank.ensureTotalCapacity(allocator, capacity);
            try self.left.ensureTotalCapacity(allocator, capacity);
            try self.left_version.ensureTotalCapacity(allocator, capacity);
            try self.right_version.ensureTotalCapacity(allocator, capacity);
            try self.next.ensureTotalCapacity(allocator, capacity);
        }

        fn allocIndex(self: *CandidatePool, allocator: std.mem.Allocator) !CandidateIndex {
            if (self.free_head != invalid_candidate) {
                const idx = self.free_head;
                self.free_head = self.next.items[@as(usize, idx)];
                return idx;
            }

            const idx = self.rank.items.len;
            if (idx >= invalid_candidate) {
                return error.OutOfMemory;
            }

            try self.rank.append(allocator, 0);
            try self.left.append(allocator, 0);
            try self.left_version.append(allocator, 0);
            try self.right_version.append(allocator, 0);
            try self.next.append(allocator, invalid_candidate);
            return @as(CandidateIndex, @intCast(idx));
        }

        fn set(self: *CandidatePool, idx: CandidateIndex, candidate: Candidate, next_idx: CandidateIndex) void {
            const i = @as(usize, idx);
            self.rank.items[i] = candidate.rank;
            self.left.items[i] = candidate.left;
            self.left_version.items[i] = candidate.left_version;
            self.right_version.items[i] = candidate.right_version;
            self.next.items[i] = next_idx;
        }

        fn get(self: *const CandidatePool, idx: CandidateIndex) Candidate {
            const i = @as(usize, idx);
            return .{
                .rank = self.rank.items[i],
                .left = self.left.items[i],
                .left_version = self.left_version.items[i],
                .right_version = self.right_version.items[i],
            };
        }

        fn nextIndex(self: *const CandidatePool, idx: CandidateIndex) CandidateIndex {
            return self.next.items[@as(usize, idx)];
        }

        fn release(self: *CandidatePool, idx: CandidateIndex) void {
            self.next.items[@as(usize, idx)] = self.free_head;
            self.free_head = idx;
        }
    };

    const BucketQueue = struct {
        allocator: std.mem.Allocator,
        pool: CandidatePool = .{},
        bucket_heads: []CandidateIndex,
        min_nonempty: usize,
        overflow_enabled: bool,
        overflow_heap: std.ArrayListUnmanaged(CandidateIndex) = .{},

        fn init(allocator: std.mem.Allocator, bucket_count: usize, overflow_enabled: bool) !BucketQueue {
            const queue: BucketQueue = .{
                .allocator = allocator,
                .bucket_heads = try allocator.alloc(CandidateIndex, bucket_count),
                .min_nonempty = bucket_count,
                .overflow_enabled = overflow_enabled,
            };
            @memset(queue.bucket_heads, invalid_candidate);
            return queue;
        }

        fn deinit(self: *BucketQueue) void {
            self.pool.deinit(self.allocator);
            if (self.overflow_enabled) {
                self.overflow_heap.deinit(self.allocator);
            }
            self.allocator.free(self.bucket_heads);
        }

        fn ensureTotalCapacity(self: *BucketQueue, capacity: usize) !void {
            try self.pool.ensureTotalCapacity(self.allocator, capacity);
            if (self.overflow_enabled) {
                try self.overflow_heap.ensureTotalCapacity(self.allocator, capacity / 4 + 1);
            }
        }

        fn add(self: *BucketQueue, candidate: Candidate) !void {
            const idx = try self.pool.allocIndex(self.allocator);
            if (candidate.rank < self.bucket_heads.len) {
                const bucket = @as(usize, @intCast(candidate.rank));
                const head = self.bucket_heads[bucket];
                self.pool.set(idx, candidate, head);
                self.bucket_heads[bucket] = idx;
                if (bucket < self.min_nonempty) {
                    self.min_nonempty = bucket;
                }
            } else if (self.overflow_enabled) {
                self.pool.set(idx, candidate, invalid_candidate);
                try self.overflowPush(idx);
            } else {
                self.pool.release(idx);
                return error.RankOutOfRange;
            }
        }

        fn removeOrNull(self: *BucketQueue) ?Candidate {
            if (!self.overflow_enabled) {
                const idx = self.popBucketHead() orelse return null;
                const candidate = self.pool.get(idx);
                self.pool.release(idx);
                return candidate;
            }

            const bucket_idx_opt = self.peekBucketHead();
            const overflow_idx_opt = self.peekOverflowHead();

            const choice: QueueChoice = blk: {
                if (bucket_idx_opt == null and overflow_idx_opt == null) {
                    return null;
                }
                if (bucket_idx_opt == null) {
                    break :blk .overflow;
                }
                if (overflow_idx_opt == null) {
                    break :blk .bucket;
                }

                break :blk switch (self.compareCandidateIndices(bucket_idx_opt.?, overflow_idx_opt.?)) {
                    .gt => .overflow,
                    else => .bucket,
                };
            };

            const idx = switch (choice) {
                .bucket => self.popBucketHead().?,
                .overflow => self.popOverflowHead().?,
            };
            const candidate = self.pool.get(idx);
            self.pool.release(idx);
            return candidate;
        }

        fn peekOrNull(self: *BucketQueue) ?Candidate {
            if (!self.overflow_enabled) {
                if (self.peekBucketHead()) |idx| {
                    return self.pool.get(idx);
                }
                return null;
            }

            const bucket_idx_opt = self.peekBucketHead();
            const overflow_idx_opt = self.peekOverflowHead();

            if (bucket_idx_opt == null and overflow_idx_opt == null) {
                return null;
            }
            if (bucket_idx_opt == null) {
                return self.pool.get(overflow_idx_opt.?);
            }
            if (overflow_idx_opt == null) {
                return self.pool.get(bucket_idx_opt.?);
            }

            return switch (self.compareCandidateIndices(bucket_idx_opt.?, overflow_idx_opt.?)) {
                .gt => self.pool.get(overflow_idx_opt.?),
                else => self.pool.get(bucket_idx_opt.?),
            };
        }

        fn peekBucketHead(self: *BucketQueue) ?CandidateIndex {
            self.advanceMinNonEmpty();
            if (self.min_nonempty >= self.bucket_heads.len) {
                return null;
            }
            return self.bucket_heads[self.min_nonempty];
        }

        fn popBucketHead(self: *BucketQueue) ?CandidateIndex {
            self.advanceMinNonEmpty();
            if (self.min_nonempty >= self.bucket_heads.len) {
                return null;
            }

            const head = self.bucket_heads[self.min_nonempty];
            self.bucket_heads[self.min_nonempty] = self.pool.nextIndex(head);
            if (self.bucket_heads[self.min_nonempty] == invalid_candidate) {
                self.advanceMinNonEmpty();
            }
            return head;
        }

        fn advanceMinNonEmpty(self: *BucketQueue) void {
            while (self.min_nonempty < self.bucket_heads.len and self.bucket_heads[self.min_nonempty] == invalid_candidate) {
                self.min_nonempty += 1;
            }
        }

        fn peekOverflowHead(self: *const BucketQueue) ?CandidateIndex {
            if (!self.overflow_enabled) {
                return null;
            }
            if (self.overflow_heap.items.len == 0) {
                return null;
            }
            return self.overflow_heap.items[0];
        }

        fn popOverflowHead(self: *BucketQueue) ?CandidateIndex {
            if (!self.overflow_enabled) {
                return null;
            }
            if (self.overflow_heap.items.len == 0) {
                return null;
            }

            const min_idx = self.overflow_heap.items[0];
            const last_idx = self.overflow_heap.pop().?;
            if (self.overflow_heap.items.len > 0) {
                self.overflow_heap.items[0] = last_idx;
                self.overflowSiftDown(0);
            }
            return min_idx;
        }

        fn overflowPush(self: *BucketQueue, idx: CandidateIndex) !void {
            if (!self.overflow_enabled) {
                return error.RankOutOfRange;
            }
            try self.overflow_heap.append(self.allocator, idx);
            var child = self.overflow_heap.items.len - 1;
            while (child > 0) {
                const parent = (child - 1) / 2;
                if (self.compareCandidateIndices(self.overflow_heap.items[child], self.overflow_heap.items[parent]) != .lt) {
                    break;
                }
                std.mem.swap(CandidateIndex, &self.overflow_heap.items[child], &self.overflow_heap.items[parent]);
                child = parent;
            }
        }

        fn overflowSiftDown(self: *BucketQueue, start_idx: usize) void {
            var parent = start_idx;
            const len = self.overflow_heap.items.len;
            while (true) {
                const left = parent * 2 + 1;
                if (left >= len) {
                    break;
                }

                var smallest = left;
                const right = left + 1;
                if (right < len and self.compareCandidateIndices(self.overflow_heap.items[right], self.overflow_heap.items[left]) == .lt) {
                    smallest = right;
                }

                if (self.compareCandidateIndices(self.overflow_heap.items[smallest], self.overflow_heap.items[parent]) != .lt) {
                    break;
                }
                std.mem.swap(CandidateIndex, &self.overflow_heap.items[parent], &self.overflow_heap.items[smallest]);
                parent = smallest;
            }
        }

        fn compareCandidateIndices(self: *const BucketQueue, lhs_idx: CandidateIndex, rhs_idx: CandidateIndex) std.math.Order {
            const lhs_i = @as(usize, lhs_idx);
            const rhs_i = @as(usize, rhs_idx);

            const rank_order = std.math.order(self.pool.rank.items[lhs_i], self.pool.rank.items[rhs_i]);
            if (rank_order != .eq) {
                return rank_order;
            }
            return std.math.order(self.pool.left.items[lhs_i], self.pool.left.items[rhs_i]);
        }
    };

    const QueueChoice = enum {
        bucket,
        overflow,
    };
    const cache_miss = std.math.maxInt(u32);
    const MergeResult = struct {
        arena: NodeArena,
        head_idx: NodeIndex,
    };
    const QueueConfig = struct {
        bucket_count: usize,
        overflow_enabled: bool,
    };

    fn compareCandidate(a: Candidate, b: Candidate) std.math.Order {
        const rank_order = std.math.order(a.rank, b.rank);
        if (rank_order != .eq) {
            return rank_order;
        }

        const left_order = std.math.order(a.left, b.left);
        return left_order;
    }

    fn initQueueMode() void {
        const mode = std.process.getEnvVarOwned(std.heap.page_allocator, "TURBOTOKEN_ENCODER_QUEUE") catch {
            selected_queue_mode = .full_bucket;
            return;
        };
        defer std.heap.page_allocator.free(mode);

        if (std.ascii.eqlIgnoreCase(mode, "full-bucket") or
            std.ascii.eqlIgnoreCase(mode, "full_bucket") or
            std.ascii.eqlIgnoreCase(mode, "full"))
        {
            selected_queue_mode = .full_bucket;
            return;
        }
        if (std.ascii.eqlIgnoreCase(mode, "hybrid")) {
            selected_queue_mode = .hybrid;
            return;
        }
        selected_queue_mode = .full_bucket;
    }

    fn queueMode() QueueMode {
        queue_mode_once.call();
        return selected_queue_mode;
    }

    fn resolveQueueConfig(table: *const rank_loader.RankTable) QueueConfig {
        if (queueMode() != .full_bucket) {
            return .{
                .bucket_count = candidate_bucket_count,
                .overflow_enabled = true,
            };
        }

        const rank_upper_bound = table.maxRankPlusOne();
        if (rank_upper_bound == 0) {
            return .{
                .bucket_count = candidate_bucket_count,
                .overflow_enabled = true,
            };
        }

        const capped = @min(rank_upper_bound, max_full_bucket_count);
        const bucket_count = @max(capped, candidate_bucket_count);
        return .{
            .bucket_count = bucket_count,
            .overflow_enabled = rank_upper_bound > bucket_count,
        };
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
        queue: *BucketQueue,
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

        const left_token = arena.token[left_idx];
        const right_token = arena.token[right_usize];
        const rank = try pairRank(allocator, table, cache, scratch, left_token, right_token) orelse return;

        try queue.add(.{
            .left = @as(NodeIndex, @intCast(left_idx)),
            .rank = rank,
            .left_version = arena.version[left_idx],
            .right_version = arena.version[right_usize],
        });
    }

    fn prepareReusablePairCache(
        cache: *pair_cache.PairCache,
        table: *const rank_loader.RankTable,
    ) void {
        cache.clear();
        _ = cache.populateFromKnownSeedSets(table);
    }

    fn buildMergedNodesWithReusableState(
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
    ) !MergeResult {
        if (text.len > @as(usize, dead_index)) {
            return error.InputTooLarge;
        }

        var arena = try NodeArena.init(allocator, text.len);
        errdefer arena.deinit(allocator);

        if (table.hasAllSingleByteTokens()) {
            for (text, 0..) |byte, idx| {
                const byte_token = table.singleByteTokenRank(byte).?;
                const idx_u32 = @as(u32, @intCast(idx));
                arena.start[idx] = idx_u32;
                arena.end[idx] = idx_u32 + 1;
                arena.token[idx] = byte_token;
                arena.prev[idx] = if (idx == 0) null_index else @as(NodeIndex, @intCast(idx - 1));
                arena.next[idx] = if (idx + 1 < text.len) @as(NodeIndex, @intCast(idx + 1)) else null_index;
                arena.version[idx] = 0;
            }
        } else {
            for (text, 0..) |byte, idx| {
                const byte_token = table.singleByteTokenRank(byte) orelse table.get(text[idx .. idx + 1]) orelse return error.UnknownToken;
                const idx_u32 = @as(u32, @intCast(idx));
                arena.start[idx] = idx_u32;
                arena.end[idx] = idx_u32 + 1;
                arena.token[idx] = byte_token;
                arena.prev[idx] = if (idx == 0) null_index else @as(NodeIndex, @intCast(idx - 1));
                arena.next[idx] = if (idx + 1 < text.len) @as(NodeIndex, @intCast(idx + 1)) else null_index;
                arena.version[idx] = 0;
            }
        }

        const queue_config = resolveQueueConfig(table);
        var queue = try BucketQueue.init(allocator, queue_config.bucket_count, queue_config.overflow_enabled);
        defer queue.deinit();

        if (arena.token.len > 1) {
            try queue.ensureTotalCapacity(arena.token.len - 1);
            for (0..arena.token.len - 1) |idx| {
                try enqueueCandidate(allocator, &queue, &arena, table, cache, scratch, idx);
            }
        }

        while (queue.removeOrNull()) |candidate| {
            if (queue.peekOrNull()) |next_candidate| {
                const next_left_idx = @as(usize, next_candidate.left);
                if (next_left_idx < arena.token.len) {
                    prefetchRead(2, &arena.token[next_left_idx]);
                    prefetchRead(2, &arena.next[next_left_idx]);
                }
            }

            const left_idx = @as(usize, candidate.left);
            if (left_idx >= arena.token.len) {
                continue;
            }

            if (!arena.isAlive(left_idx) or arena.version[left_idx] != candidate.left_version) {
                continue;
            }

            const actual_right_idx = arena.next[left_idx];
            if (actual_right_idx == null_index or actual_right_idx == dead_index) {
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
                prefetchRead(3, &cache.entries[prev_rank_slot]);
            }
            if (next_next_idx != null_index and next_next_idx != dead_index) {
                const next_next_usize = @as(usize, next_next_idx);
                const next_rank_slot = cache.slotIndexFor(candidate.rank, arena.token[next_next_usize]);
                prefetchRead(3, &cache.entries[next_rank_slot]);
            }

            arena.end[left_idx] = arena.end[actual_right_usize];
            arena.token[left_idx] = candidate.rank;
            arena.next[left_idx] = next_next_idx;
            arena.version[left_idx] +%= 1;

            if (next_next_idx != null_index and next_next_idx != dead_index) {
                const next_idx = @as(usize, next_next_idx);
                arena.prev[next_idx] = candidate.left;
            }

            arena.prev[actual_right_usize] = dead_index;
            arena.next[actual_right_usize] = dead_index;
            arena.version[actual_right_usize] +%= 1;

            if (prev_idx != null_index and prev_idx != dead_index) {
                try enqueueCandidate(allocator, &queue, &arena, table, cache, scratch, @as(usize, prev_idx));
            }
            try enqueueCandidate(allocator, &queue, &arena, table, cache, scratch, left_idx);
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

    fn buildMergedNodes(
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
    ) !MergeResult {
        const cache = try allocator.create(pair_cache.PairCache);
        defer allocator.destroy(cache);
        prepareReusablePairCache(cache, table);

        var scratch = std.ArrayListUnmanaged(u8){};
        defer scratch.deinit(allocator);

        return buildMergedNodesWithReusableState(allocator, text, table, cache, &scratch);
    }

    fn prefetchRead(comptime locality: u2, ptr: anytype) void {
        if (comptime builtin.cpu.arch != .wasm32 and builtin.os.tag != .freestanding) {
            @prefetch(ptr, .{ .rw = .read, .locality = locality });
        }
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
        if (builtin.cpu.arch == .x86_64 and x86_64.available() and text.len >= 16) {
            x86_64.encodeU8ToU32(text, out);
            return out;
        }
        if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable() and text.len >= 16) {
            wasm_arch.encodeU8ToU32(text, out);
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
        try out.ensureTotalCapacity(allocator, text.len);

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

    pub fn preparePairCache(
        self: *const Encoder,
        cache: *pair_cache.PairCache,
        table: *const rank_loader.RankTable,
    ) void {
        _ = self;
        prepareReusablePairCache(cache, table);
    }

    pub fn encodeWithRanksReusable(
        self: *const Encoder,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
    ) ![]u32 {
        _ = self;

        if (text.len == 0) {
            return allocator.alloc(u32, 0);
        }

        var merged = try buildMergedNodesWithReusableState(allocator, text, table, cache, scratch);
        defer merged.arena.deinit(allocator);
        const arena = &merged.arena;

        var out = std.ArrayListUnmanaged(u32){};
        errdefer out.deinit(allocator);
        try out.ensureTotalCapacity(allocator, text.len);

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

    pub fn countWithRanksReusable(
        self: *const Encoder,
        allocator: std.mem.Allocator,
        text: []const u8,
        table: *const rank_loader.RankTable,
        cache: *pair_cache.PairCache,
        scratch: *std.ArrayListUnmanaged(u8),
    ) !usize {
        _ = self;

        if (text.len == 0) {
            return 0;
        }

        var merged = try buildMergedNodesWithReusableState(allocator, text, table, cache, scratch);
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

test "reusable pair cache preserves encode/count results across pieces" {
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
    const cache = try allocator.create(pair_cache.PairCache);
    defer allocator.destroy(cache);
    enc.preparePairCache(cache, &table);

    var scratch = std.ArrayListUnmanaged(u8){};
    defer scratch.deinit(allocator);

    const tokens_abc = try enc.encodeWithRanksReusable(allocator, "abc", &table, cache, &scratch);
    defer allocator.free(tokens_abc);
    try std.testing.expectEqualSlices(u32, &[_]u32{7}, tokens_abc);

    const tokens_abcd = try enc.encodeWithRanksReusable(allocator, "abcd", &table, cache, &scratch);
    defer allocator.free(tokens_abcd);
    try std.testing.expectEqualSlices(u32, &[_]u32{9}, tokens_abcd);

    try std.testing.expectEqual(@as(usize, 1), try enc.countWithRanksReusable(allocator, "abc", &table, cache, &scratch));
    try std.testing.expectEqual(@as(usize, 1), try enc.countWithRanksReusable(allocator, "abcd", &table, cache, &scratch));
}
