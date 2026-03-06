const std = @import("std");
const builtin = @import("builtin");
const hash = @import("hash.zig");

pub const PairKey = u64;

const aarch64_crc_supported = builtin.cpu.arch == .aarch64 and
    std.Target.aarch64.featureSetHas(builtin.cpu.features, .crc);
const x86_crc_supported = builtin.cpu.arch == .x86_64 and
    std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2);

extern fn turbotoken_arm64_hash_crc32_u64(key: u64) u64;
extern fn turbotoken_x86_hash_crc32_u64(key: u64) u64;

fn hashPairKey(key: PairKey) u64 {
    if (comptime aarch64_crc_supported) {
        return turbotoken_arm64_hash_crc32_u64(key);
    }
    if (comptime x86_crc_supported) {
        return turbotoken_x86_hash_crc32_u64(key);
    }
    return hash.bytes(std.mem.asBytes(&key));
}

const PairKeyContext = struct {
    pub fn hash(_: @This(), key: PairKey) u64 {
        return hashPairKey(key);
    }

    pub fn eql(_: @This(), a: PairKey, b: PairKey) bool {
        return a == b;
    }
};

fn PairMap(comptime V: type) type {
    return std.HashMapUnmanaged(PairKey, V, PairKeyContext, std.hash_map.default_max_load_percentage);
}

const PairSet = PairMap(void);

pub const Merge = struct {
    left: u32,
    right: u32,
    new_id: u32,
};

const PairDelta = struct {
    key: PairKey,
    delta: i32,
};

const HeapEntry = struct {
    key: PairKey,
    count: i64,
};

const MergeHeap = struct {
    items: std.ArrayListUnmanaged(HeapEntry) = .{},
    const arity: usize = 8;

    fn deinit(self: *MergeHeap, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = .{};
    }

    fn lessThan(a: HeapEntry, b: HeapEntry) bool {
        if (a.count != b.count) {
            return a.count > b.count;
        }
        return a.key < b.key;
    }

    fn push(self: *MergeHeap, allocator: std.mem.Allocator, entry: HeapEntry) !void {
        try self.items.append(allocator, entry);
        var child = self.items.items.len - 1;
        while (child > 0) {
            const parent = (child - 1) / arity;
            if (!lessThan(self.items.items[child], self.items.items[parent])) {
                break;
            }
            std.mem.swap(HeapEntry, &self.items.items[child], &self.items.items[parent]);
            child = parent;
        }
    }

    fn popOrNull(self: *MergeHeap) ?HeapEntry {
        if (self.items.items.len == 0) {
            return null;
        }
        const top = self.items.items[0];
        const last = self.items.items[self.items.items.len - 1];
        self.items.items.len -= 1;
        if (self.items.items.len == 0) {
            return top;
        }
        self.items.items[0] = last;
        self.siftDown(0);
        return top;
    }

    fn siftDown(self: *MergeHeap, start: usize) void {
        var parent = start;
        const len = self.items.items.len;
        while (true) {
            const first_child = parent * arity + 1;
            if (first_child >= len) {
                break;
            }
            var best = first_child;
            var child = first_child + 1;
            const child_end = @min(first_child + arity, len);
            while (child < child_end) : (child += 1) {
                if (lessThan(self.items.items[child], self.items.items[best])) {
                    best = child;
                }
            }
            if (!lessThan(self.items.items[best], self.items.items[parent])) {
                break;
            }
            std.mem.swap(HeapEntry, &self.items.items[parent], &self.items.items[best]);
            parent = best;
        }
    }
};

fn pairKey(left: u32, right: u32) PairKey {
    return (@as(u64, left) << 32) | @as(u64, right);
}

fn pairLeft(key: PairKey) u32 {
    return @as(u32, @intCast(key >> 32));
}

fn pairRight(key: PairKey) u32 {
    return @as(u32, @intCast(key & 0xFFFF_FFFF));
}

const training_parallel_min_words: usize = 1_024;
const training_parallel_min_bytes: usize = 1_048_576;
const training_target_bytes_per_worker: usize = 256 * 1024;
const training_target_words_per_worker: usize = 512;
const training_pair_map_reserve_cap: usize = 131_072;

fn trainingThreadOverride() ?usize {
    const allocator = std.heap.page_allocator;
    const raw = std.process.getEnvVarOwned(allocator, "TURBOTOKEN_NATIVE_TRAIN_THREADS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return null,
    };
    defer allocator.free(raw);
    const parsed = std.fmt.parseInt(usize, raw, 10) catch return null;
    if (parsed == 0) {
        return null;
    }
    return parsed;
}

fn capTrainingWorkerTargetByCorpus(target: usize, word_count: usize, total_bytes: usize) usize {
    const clamped_target = @max(@as(usize, 1), @min(target, word_count));
    const max_by_words = @max(
        @as(usize, 1),
        (word_count + training_target_words_per_worker - 1) / training_target_words_per_worker,
    );
    const max_by_bytes = @max(
        @as(usize, 1),
        (total_bytes + training_target_bytes_per_worker - 1) / training_target_bytes_per_worker,
    );
    return @max(@as(usize, 1), @min(clamped_target, @min(max_by_words, max_by_bytes)));
}

fn chooseTrainingWorkerCount(word_count: usize, total_bytes: usize) usize {
    if (word_count == 0) {
        return 1;
    }
    if (comptime builtin.single_threaded or builtin.os.tag == .freestanding) {
        return 1;
    }

    const cpu_count = std.Thread.getCpuCount() catch 1;
    const capped_cpu = @max(@as(usize, 1), cpu_count);
    if (trainingThreadOverride()) |override| {
        // Explicit thread override is treated as an operator upper bound rather than
        // an unconditional spawn count. This keeps small corpora from paying
        // pathological thread startup + shard merge overhead on hosted CI x64.
        const target = @max(@as(usize, 1), @min(override, capped_cpu));
        return capTrainingWorkerTargetByCorpus(target, word_count, total_bytes);
    }

    if (word_count < training_parallel_min_words or total_bytes < training_parallel_min_bytes) {
        return 1;
    }
    return @max(@as(usize, 1), @min(capped_cpu, word_count));
}

fn buildInitialPairStateSequential(
    allocator: std.mem.Allocator,
    words: []const Word,
    counts: []const u32,
    pair_counts: *PairMap(i64),
    where_to_update: *PairMap(std.AutoHashMapUnmanaged(u32, void)),
) !void {
    var seen_pairs: PairSet = .{};
    defer seen_pairs.deinit(allocator);

    for (0..words.len) |word_idx| {
        const weight = counts[word_idx];
        const ids = words[word_idx].ids.items;
        if (weight == 0 or ids.len < 2) {
            continue;
        }
        seen_pairs.clearRetainingCapacity();
        for (0..ids.len - 1) |idx| {
            const key = pairKey(ids[idx], ids[idx + 1]);
            const count_entry = try pair_counts.getOrPut(allocator, key);
            if (!count_entry.found_existing) {
                count_entry.value_ptr.* = 0;
            }
            count_entry.value_ptr.* += @as(i64, @intCast(weight));

            const seen_entry = try seen_pairs.getOrPut(allocator, key);
            if (!seen_entry.found_existing) {
                const pos_entry = try where_to_update.getOrPut(allocator, key);
                if (!pos_entry.found_existing) {
                    pos_entry.value_ptr.* = .{};
                }
                _ = try pos_entry.value_ptr.getOrPut(allocator, @as(u32, @intCast(word_idx)));
            }
        }
    }
}

const PairInitShard = struct {
    start: usize,
    end: usize,
    words: []const Word,
    counts: []const u32,
    arena: std.heap.ArenaAllocator,
    pair_counts: PairMap(i64) = .{},
    where_to_update: PairMap(std.AutoHashMapUnmanaged(u32, void)) = .{},
    failed: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    fn init(
        base_allocator: std.mem.Allocator,
        words: []const Word,
        counts: []const u32,
        start: usize,
        end: usize,
    ) PairInitShard {
        return .{
            .start = start,
            .end = end,
            .words = words,
            .counts = counts,
            .arena = std.heap.ArenaAllocator.init(base_allocator),
        };
    }

    fn allocator(self: *PairInitShard) std.mem.Allocator {
        return self.arena.allocator();
    }

    fn deinit(self: *PairInitShard) void {
        const local_allocator = self.allocator();
        var iter = self.where_to_update.valueIterator();
        while (iter.next()) |set_map| {
            set_map.deinit(local_allocator);
        }
        self.where_to_update.deinit(local_allocator);
        self.pair_counts.deinit(local_allocator);
        self.arena.deinit();
        self.* = undefined;
    }
};

fn pairInitShardWorker(shard: *PairInitShard) void {
    const allocator = shard.allocator();
    var seen_pairs: PairSet = .{};
    defer seen_pairs.deinit(allocator);

    var word_idx = shard.start;
    while (word_idx < shard.end) : (word_idx += 1) {
        const weight = shard.counts[word_idx];
        const ids = shard.words[word_idx].ids.items;
        if (weight == 0 or ids.len < 2) {
            continue;
        }
        seen_pairs.clearRetainingCapacity();
        for (0..ids.len - 1) |idx| {
            const key = pairKey(ids[idx], ids[idx + 1]);
            const count_entry = shard.pair_counts.getOrPut(allocator, key) catch {
                shard.failed.store(1, .release);
                return;
            };
            if (!count_entry.found_existing) {
                count_entry.value_ptr.* = 0;
            }
            count_entry.value_ptr.* += @as(i64, @intCast(weight));

            const seen_entry = seen_pairs.getOrPut(allocator, key) catch {
                shard.failed.store(1, .release);
                return;
            };
            if (!seen_entry.found_existing) {
                const pos_entry = shard.where_to_update.getOrPut(allocator, key) catch {
                    shard.failed.store(1, .release);
                    return;
                };
                if (!pos_entry.found_existing) {
                    pos_entry.value_ptr.* = .{};
                }
                _ = pos_entry.value_ptr.getOrPut(allocator, @as(u32, @intCast(word_idx))) catch {
                    shard.failed.store(1, .release);
                    return;
                };
            }
        }
    }
}

fn mergePairInitShard(
    allocator: std.mem.Allocator,
    shard: *const PairInitShard,
    pair_counts: *PairMap(i64),
    where_to_update: *PairMap(std.AutoHashMapUnmanaged(u32, void)),
) !void {
    var count_iter = shard.pair_counts.iterator();
    while (count_iter.next()) |entry| {
        const target = try pair_counts.getOrPut(allocator, entry.key_ptr.*);
        if (!target.found_existing) {
            target.value_ptr.* = 0;
        }
        target.value_ptr.* += entry.value_ptr.*;
    }

    var where_iter = shard.where_to_update.iterator();
    while (where_iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const target = try where_to_update.getOrPut(allocator, key);
        if (!target.found_existing) {
            target.value_ptr.* = .{};
        }
        var word_iter = entry.value_ptr.keyIterator();
        while (word_iter.next()) |word_idx_ptr| {
            _ = try target.value_ptr.getOrPut(allocator, word_idx_ptr.*);
        }
    }
}

fn buildInitialPairState(
    allocator: std.mem.Allocator,
    words: []const Word,
    counts: []const u32,
    total_bytes: usize,
    pair_counts: *PairMap(i64),
    where_to_update: *PairMap(std.AutoHashMapUnmanaged(u32, void)),
) !void {
    if (builtin.single_threaded or builtin.os.tag == .freestanding) {
        try buildInitialPairStateSequential(allocator, words, counts, pair_counts, where_to_update);
        return;
    }

    const worker_count = chooseTrainingWorkerCount(words.len, total_bytes);
    if (worker_count <= 1 or words.len <= 1) {
        try buildInitialPairStateSequential(allocator, words, counts, pair_counts, where_to_update);
        return;
    }

    const shard_count = @min(worker_count, words.len);
    const chunk = (words.len + shard_count - 1) / shard_count;
    var shards = try allocator.alloc(PairInitShard, shard_count);
    defer allocator.free(shards);
    for (0..shard_count) |idx| {
        const start = idx * chunk;
        const end = @min(words.len, start + chunk);
        shards[idx] = PairInitShard.init(std.heap.page_allocator, words, counts, start, end);
    }
    defer for (shards) |*shard| shard.deinit();

    var threads = allocator.alloc(std.Thread, shard_count - 1) catch {
        try buildInitialPairStateSequential(allocator, words, counts, pair_counts, where_to_update);
        return;
    };
    defer allocator.free(threads);

    var spawned: usize = 0;
    var spawn_failed = false;
    for (1..shard_count) |idx| {
        threads[spawned] = std.Thread.spawn(.{}, pairInitShardWorker, .{&shards[idx]}) catch {
            spawn_failed = true;
            break;
        };
        spawned += 1;
    }

    pairInitShardWorker(&shards[0]);
    for (threads[0..spawned]) |*thread| {
        thread.join();
    }

    if (spawn_failed) {
        try buildInitialPairStateSequential(allocator, words, counts, pair_counts, where_to_update);
        return;
    }
    for (shards) |*shard| {
        if (shard.failed.load(.acquire) != 0) {
            return error.OutOfMemory;
        }
    }

    for (shards) |*shard| {
        try mergePairInitShard(allocator, shard, pair_counts, where_to_update);
    }
}

const Word = struct {
    ids: std.ArrayListUnmanaged(u32) = .{},

    fn initFromBytes(allocator: std.mem.Allocator, chunk: []const u8) !Word {
        var word = Word{};
        errdefer word.deinit(allocator);
        try word.ids.ensureTotalCapacityPrecise(allocator, chunk.len);
        for (chunk) |byte| {
            word.ids.appendAssumeCapacity(@as(u32, byte));
        }
        return word;
    }

    fn deinit(self: *Word, allocator: std.mem.Allocator) void {
        self.ids.deinit(allocator);
        self.* = .{};
    }

    fn mergePair(
        self: *Word,
        allocator: std.mem.Allocator,
        left_id: u32,
        right_id: u32,
        new_id: u32,
        deltas: *std.ArrayListUnmanaged(PairDelta),
    ) !bool {
        const ids = self.ids.items;
        if (ids.len < 2) {
            return false;
        }

        var first_match: ?usize = null;
        for (0..ids.len - 1) |idx| {
            if (ids[idx] == left_id and ids[idx + 1] == right_id) {
                first_match = idx;
                break;
            }
        }
        if (first_match == null) {
            return false;
        }

        deltas.clearRetainingCapacity();
        try deltas.ensureTotalCapacity(allocator, 8);

        var write: usize = first_match.?;
        var read: usize = first_match.?;
        while (read < ids.len) {
            if (read + 1 < ids.len and ids[read] == left_id and ids[read + 1] == right_id) {
                const left_neighbor = if (write > 0) ids[write - 1] else null;
                const right_neighbor = if (read + 2 < ids.len) ids[read + 2] else null;

                if (left_neighbor) |left| {
                    try deltas.append(allocator, .{ .key = pairKey(left, left_id), .delta = -1 });
                    try deltas.append(allocator, .{ .key = pairKey(left, new_id), .delta = 1 });
                }
                try deltas.append(allocator, .{ .key = pairKey(left_id, right_id), .delta = -1 });
                if (right_neighbor) |right| {
                    try deltas.append(allocator, .{ .key = pairKey(right_id, right), .delta = -1 });
                    try deltas.append(allocator, .{ .key = pairKey(new_id, right), .delta = 1 });
                }

                ids[write] = new_id;
                write += 1;
                read += 2;
            } else {
                ids[write] = ids[read];
                write += 1;
                read += 1;
            }
        }

        self.ids.items.len = write;
        return true;
    }
};

pub const CountedChunk = struct {
    bytes: []const u8,
    count: u32,
};

fn validateChunkInputs(
    chunks: []const u8,
    offsets: []const u32,
    counts: []const u32,
) !void {
    if (offsets.len == 0) {
        return error.InvalidInput;
    }
    if (counts.len + 1 != offsets.len) {
        return error.InvalidInput;
    }
    if (offsets[0] != 0) {
        return error.InvalidInput;
    }
    if (offsets[offsets.len - 1] != chunks.len) {
        return error.InvalidInput;
    }
    var prev: u32 = offsets[0];
    for (offsets[1..]) |next| {
        if (next < prev or next > chunks.len) {
            return error.InvalidInput;
        }
        prev = next;
    }
}

fn trainPreparedWords(
    allocator: std.mem.Allocator,
    work_allocator: std.mem.Allocator,
    words: []Word,
    counts: []const u32,
    total_bytes: usize,
    vocab_size: u32,
    min_frequency: u32,
) ![]Merge {
    const word_count = counts.len;
    if (word_count == 0) {
        return try allocator.alloc(Merge, 0);
    }
    if (word_count > std.math.maxInt(u32)) {
        return error.InvalidInput;
    }

    var initial_pair_slots: usize = 0;
    for (words) |word| {
        if (word.ids.items.len > 1) {
            initial_pair_slots +|= word.ids.items.len - 1;
        }
    }

    const pair_map_reserve = @max(
        @as(usize, 1),
        @min(initial_pair_slots, training_pair_map_reserve_cap),
    );

    var pair_counts: PairMap(i64) = .{};
    defer pair_counts.deinit(work_allocator);
    try pair_counts.ensureTotalCapacity(work_allocator, pair_map_reserve);

    var where_to_update: PairMap(std.AutoHashMapUnmanaged(u32, void)) = .{};
    defer {
        var iter = where_to_update.valueIterator();
        while (iter.next()) |set_map| {
            set_map.deinit(work_allocator);
        }
        where_to_update.deinit(work_allocator);
    }
    try where_to_update.ensureTotalCapacity(work_allocator, pair_map_reserve);
    try buildInitialPairState(
        work_allocator,
        words,
        counts,
        total_bytes,
        &pair_counts,
        &where_to_update,
    );

    const max_merges = vocab_size - 256;
    var merges = std.ArrayListUnmanaged(Merge){};
    defer merges.deinit(work_allocator);
    try merges.ensureTotalCapacityPrecise(work_allocator, max_merges);

    var deltas = std.ArrayListUnmanaged(PairDelta){};
    defer deltas.deinit(work_allocator);
    try deltas.ensureTotalCapacity(work_allocator, 8);

    var seen_positive: PairSet = .{};
    defer seen_positive.deinit(work_allocator);
    try seen_positive.ensureTotalCapacity(work_allocator, 128);

    var candidate_indices: std.ArrayListUnmanaged(u32) = .{};
    defer candidate_indices.deinit(work_allocator);
    try candidate_indices.ensureTotalCapacity(work_allocator, 256);
    var local_changed_pairs: PairSet = .{};
    defer local_changed_pairs.deinit(work_allocator);
    try local_changed_pairs.ensureTotalCapacity(work_allocator, 256);

    var heap: MergeHeap = .{};
    defer heap.deinit(work_allocator);
    {
        var init_iter = pair_counts.iterator();
        while (init_iter.next()) |entry| {
            const count = entry.value_ptr.*;
            if (count >= @as(i64, @intCast(min_frequency))) {
                try heap.push(work_allocator, .{
                    .key = entry.key_ptr.*,
                    .count = count,
                });
            }
        }
    }

    while (merges.items.len < max_merges) {
        var selected: ?HeapEntry = null;
        while (heap.popOrNull()) |candidate| {
            const current = pair_counts.get(candidate.key) orelse 0;
            if (current < @as(i64, @intCast(min_frequency))) {
                continue;
            }
            if (current != candidate.count) {
                try heap.push(work_allocator, .{
                    .key = candidate.key,
                    .count = current,
                });
                continue;
            }
            selected = candidate;
            break;
        }

        if (selected == null) {
            break;
        }

        const selected_key = selected.?.key;
        const selected_left = pairLeft(selected_key);
        const selected_right = pairRight(selected_key);
        const new_id = @as(u32, @intCast(256 + merges.items.len));
        try merges.append(work_allocator, .{
            .left = selected_left,
            .right = selected_right,
            .new_id = new_id,
        });

        candidate_indices.clearRetainingCapacity();
        if (where_to_update.getPtr(selected_key)) |indices_set_ptr| {
            var word_iter = indices_set_ptr.keyIterator();
            while (word_iter.next()) |word_idx_ptr| {
                try candidate_indices.append(work_allocator, word_idx_ptr.*);
            }
            indices_set_ptr.deinit(work_allocator);
            _ = where_to_update.remove(selected_key);
        }
        for (candidate_indices.items) |word_idx_u32| {
            const word_idx = @as(usize, @intCast(word_idx_u32));
            if (word_idx >= words.len or counts[word_idx] == 0) {
                continue;
            }
            const merged = try words[word_idx].mergePair(
                work_allocator,
                selected_left,
                selected_right,
                new_id,
                &deltas,
            );
            if (!merged) {
                continue;
            }

            const weight = @as(i64, @intCast(counts[word_idx]));
            seen_positive.clearRetainingCapacity();
            for (deltas.items) |delta| {
                const delta_total = @as(i64, delta.delta) * weight;
                if (delta_total == 0) {
                    continue;
                }

                const count_entry = try pair_counts.getOrPut(work_allocator, delta.key);
                if (!count_entry.found_existing) {
                    count_entry.value_ptr.* = 0;
                }
                count_entry.value_ptr.* += delta_total;
                if (count_entry.value_ptr.* <= 0) {
                    _ = pair_counts.remove(delta.key);
                }

                if (delta.delta > 0) {
                    const seen_entry = try seen_positive.getOrPut(work_allocator, delta.key);
                    if (!seen_entry.found_existing) {
                        const pos_entry = try where_to_update.getOrPut(work_allocator, delta.key);
                        if (!pos_entry.found_existing) {
                            pos_entry.value_ptr.* = .{};
                        }
                        _ = try pos_entry.value_ptr.getOrPut(work_allocator, @as(u32, @intCast(word_idx)));
                        _ = try local_changed_pairs.getOrPut(work_allocator, delta.key);
                    }
                }
            }
        }
        {
            var changed_iter = local_changed_pairs.keyIterator();
            while (changed_iter.next()) |pair_key_ptr| {
                const key = pair_key_ptr.*;
                const next_count = pair_counts.get(key) orelse 0;
                if (next_count >= @as(i64, @intCast(min_frequency))) {
                    try heap.push(work_allocator, .{
                        .key = key,
                        .count = next_count,
                    });
                }
            }
            local_changed_pairs.clearRetainingCapacity();
        }
        _ = pair_counts.remove(selected_key);
    }
    const out = try allocator.alloc(Merge, merges.items.len);
    @memcpy(out, merges.items);
    return out;
}

pub fn trainMergesFromCountedChunks(
    allocator: std.mem.Allocator,
    counted_chunks: []const CountedChunk,
    vocab_size: u32,
    min_frequency: u32,
) ![]Merge {
    if (vocab_size < 256) {
        return error.InvalidInput;
    }
    if (min_frequency == 0) {
        return error.InvalidInput;
    }
    if (counted_chunks.len == 0) {
        return try allocator.alloc(Merge, 0);
    }
    if (counted_chunks.len > std.math.maxInt(u32)) {
        return error.InvalidInput;
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const work_allocator = arena_state.allocator();

    var words = try work_allocator.alloc(Word, counted_chunks.len);
    for (words) |*word| word.* = .{};
    defer for (words) |*word| word.deinit(work_allocator);

    const counts = try work_allocator.alloc(u32, counted_chunks.len);
    var total_bytes: usize = 0;
    for (counted_chunks, 0..) |chunk, idx| {
        words[idx] = try Word.initFromBytes(work_allocator, chunk.bytes);
        counts[idx] = chunk.count;
        total_bytes +|= chunk.bytes.len;
    }

    return trainPreparedWords(
        allocator,
        work_allocator,
        words,
        counts,
        total_bytes,
        vocab_size,
        min_frequency,
    );
}

pub fn trainMergesFromChunkCounts(
    allocator: std.mem.Allocator,
    chunks: []const u8,
    offsets: []const u32,
    counts: []const u32,
    vocab_size: u32,
    min_frequency: u32,
) ![]Merge {
    if (vocab_size < 256) {
        return error.InvalidInput;
    }
    if (min_frequency == 0) {
        return error.InvalidInput;
    }
    try validateChunkInputs(chunks, offsets, counts);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const work_allocator = arena_state.allocator();

    const word_count = counts.len;
    var words = try work_allocator.alloc(Word, word_count);
    for (words) |*word| word.* = .{};
    for (0..word_count) |idx| {
        const start = offsets[idx];
        const end = offsets[idx + 1];
        words[idx] = try Word.initFromBytes(work_allocator, chunks[start..end]);
    }
    defer for (words) |*word| word.deinit(work_allocator);
    return trainPreparedWords(
        allocator,
        work_allocator,
        words,
        counts,
        chunks.len,
        vocab_size,
        min_frequency,
    );
}

test "trainMergesFromChunkCounts learns repeated pair" {
    const allocator = std.testing.allocator;
    const chunks = "abab";
    const offsets = [_]u32{ 0, 4 };
    const counts = [_]u32{1};

    const merges = try trainMergesFromChunkCounts(
        allocator,
        chunks,
        &offsets,
        &counts,
        257,
        1,
    );
    defer allocator.free(merges);

    try std.testing.expectEqual(@as(usize, 1), merges.len);
    try std.testing.expectEqual(@as(u32, 97), merges[0].left);
    try std.testing.expectEqual(@as(u32, 98), merges[0].right);
    try std.testing.expectEqual(@as(u32, 256), merges[0].new_id);
}

test "training worker cap keeps small corpora single-threaded even with large target" {
    try std.testing.expectEqual(@as(usize, 1), capTrainingWorkerTargetByCorpus(8, 4_096, 100 * 1024));
    try std.testing.expectEqual(@as(usize, 4), capTrainingWorkerTargetByCorpus(8, 16_384, 1_024 * 1_024));
}
