const std = @import("std");
const builtin = @import("builtin");
const rank_loader = @import("rank_loader.zig");
const hash = @import("hash.zig");
const generated_seeds = @import("generated/pair_cache_seeds.zig");

pub const bytes: usize = 4 * 1024 * 1024;
pub const empty_key: u64 = std.math.maxInt(u64);

const Entry = extern struct {
    key: u64,
    value: u32,
    _reserved: u32 = 0,
};

pub const entry_count: usize = bytes / @sizeOf(Entry);

pub const PairCache = struct {
    const HashMode = enum {
        rapidhash,
        crc32,
    };
    const aarch64_crc_supported = builtin.cpu.arch == .aarch64 and
        std.Target.aarch64.featureSetHas(builtin.cpu.features, .crc);
    const x86_crc_supported = builtin.cpu.arch == .x86_64 and
        std.Target.x86.featureSetHas(builtin.cpu.features, .sse4_2);
    const hash_mode_benchmark_iterations: usize = 512;

    extern fn turbotoken_arm64_hash_crc32_u64(key: u64) u64;
    extern fn turbotoken_x86_hash_crc32_u64(key: u64) u64;

    var selected_hash_mode: HashMode = .rapidhash;
    var selected_hash_mode_once = std.once(initHashMode);

    entries: [entry_count]Entry align(64),

    pub fn init() PairCache {
        var cache: PairCache = undefined;
        cache.clear();
        return cache;
    }

    pub fn clear(self: *PairCache) void {
        for (&self.entries) |*entry| {
            entry.key = empty_key;
            entry.value = 0;
            entry._reserved = 0;
        }
    }

    pub fn put(self: *PairCache, left: u32, right: u32, value: u32) bool {
        const key = packPair(left, right);
        var idx = slotIndex(key);

        var probes: usize = 0;
        while (probes < entry_count) : (probes += 1) {
            const entry = &self.entries[idx];
            if (entry.key == empty_key or entry.key == key) {
                entry.key = key;
                entry.value = value;
                return true;
            }

            idx = (idx + 1) & (entry_count - 1);
        }

        return false;
    }

    pub fn get(self: *const PairCache, left: u32, right: u32) ?u32 {
        const key = packPair(left, right);
        var idx = slotIndex(key);

        var probes: usize = 0;
        while (probes < entry_count) : (probes += 1) {
            const entry = &self.entries[idx];
            if (entry.key == key) {
                return entry.value;
            }
            if (entry.key == empty_key) {
                return null;
            }

            idx = (idx + 1) & (entry_count - 1);
        }

        return null;
    }

    pub fn slotIndexFor(_: *const PairCache, left: u32, right: u32) usize {
        return slotIndex(packPair(left, right));
    }

    pub fn usedSlots(self: *const PairCache) usize {
        var used: usize = 0;
        for (self.entries) |entry| {
            if (entry.key != empty_key) {
                used += 1;
            }
        }
        return used;
    }

    pub fn populateFromRankTable(self: *PairCache, table: *const rank_loader.RankTable) void {
        for (table.by_rank_dense.items, 0..) |maybe_token, rank_idx| {
            const token = maybe_token orelse continue;
            if (token.len < 2) {
                continue;
            }

            const rank: u32 = @intCast(rank_idx);
            var split_at: usize = 1;
            while (split_at < token.len) : (split_at += 1) {
                const left = table.get(token[0..split_at]) orelse continue;
                const right = table.get(token[split_at..]) orelse continue;
                _ = self.put(left, right, rank);
            }
        }
    }

    pub fn populateFromKnownSeedSets(self: *PairCache, table: *const rank_loader.RankTable) bool {
        const fingerprint = rankTableFingerprint(table, generated_seeds.fingerprint_token_limit);
        inline for (generated_seeds.seed_sets) |seed_set| {
            if (seed_set.fingerprint == fingerprint) {
                self.populateFromSeedPairs(seed_set.pairs);
                return true;
            }
        }
        return false;
    }

    fn populateFromSeedPairs(self: *PairCache, pairs: []const generated_seeds.SeedPair) void {
        for (pairs) |pair| {
            _ = self.put(pair.left, pair.right, pair.rank);
        }
    }

    fn packPair(left: u32, right: u32) u64 {
        return (@as(u64, left) << 32) | @as(u64, right);
    }

    fn slotIndex(key: u64) usize {
        const slot_hash = hashKey(selectHashMode(), key);
        return @as(usize, @truncate(slot_hash)) & (entry_count - 1);
    }

    fn selectHashMode() HashMode {
        selected_hash_mode_once.call();
        return selected_hash_mode;
    }

    fn defaultHashMode() HashMode {
        if (comptime aarch64_crc_supported) {
            return .crc32;
        }
        if (comptime x86_crc_supported) {
            return selectFastestHashMode();
        }
        return .rapidhash;
    }

    fn initHashMode() void {
        if (builtin.os.tag == .freestanding) {
            selected_hash_mode = defaultHashMode();
            return;
        }

        const mode = std.process.getEnvVarOwned(std.heap.page_allocator, "TURBOTOKEN_PAIR_CACHE_HASH") catch {
            selected_hash_mode = defaultHashMode();
            return;
        };
        defer std.heap.page_allocator.free(mode);

        if (std.ascii.eqlIgnoreCase(mode, "rapidhash")) {
            selected_hash_mode = .rapidhash;
            return;
        }
        if (std.ascii.eqlIgnoreCase(mode, "crc32")) {
            selected_hash_mode = if (comptime aarch64_crc_supported or x86_crc_supported) .crc32 else .rapidhash;
            return;
        }
        selected_hash_mode = defaultHashMode();
    }

    fn hashKey(mode: HashMode, key: u64) u64 {
        return switch (mode) {
            .rapidhash => hash.bytes(std.mem.asBytes(&key)),
            .crc32 => blk: {
                if (comptime aarch64_crc_supported) {
                    break :blk turbotoken_arm64_hash_crc32_u64(key);
                }
                if (comptime x86_crc_supported) {
                    break :blk turbotoken_x86_hash_crc32_u64(key);
                }
                break :blk hash.bytes(std.mem.asBytes(&key));
            },
        };
    }

    fn selectFastestHashMode() HashMode {
        var sample: [256]u64 = undefined;
        for (&sample, 0..) |*slot, idx| {
            slot.* = (@as(u64, @intCast(idx + 1)) *% 0x9e3779b97f4a7c15) ^ 0x4cf5ad432745937f;
        }

        const rapidhash_time = benchmarkHashModeBestOf3(.rapidhash, &sample, hash_mode_benchmark_iterations);
        const crc32_time = benchmarkHashModeBestOf3(.crc32, &sample, hash_mode_benchmark_iterations);
        if (crc32_time * 100 <= rapidhash_time * 99) {
            return .crc32;
        }
        return .rapidhash;
    }

    fn benchmarkHashModeBestOf3(mode: HashMode, sample: []const u64, iterations: usize) u64 {
        var best: u64 = std.math.maxInt(u64);
        for (0..3) |_| {
            best = @min(best, benchmarkHashMode(mode, sample, iterations));
        }
        return best;
    }

    fn benchmarkHashMode(mode: HashMode, sample: []const u64, iterations: usize) u64 {
        var sink: u64 = 0;
        var timer = std.time.Timer.start() catch return std.math.maxInt(u64);

        var iter: usize = 0;
        while (iter < iterations) : (iter += 1) {
            for (sample) |key| {
                sink +%= hashKey(mode, key);
            }
        }

        std.mem.doNotOptimizeAway(sink);
        return timer.read();
    }

    fn rankTableFingerprint(table: *const rank_loader.RankTable, limit: u32) u64 {
        var fingerprint: u64 = 0xcbf29ce484222325;
        var rank: u32 = 0;

        while (rank < limit) : (rank += 1) {
            const token = table.tokenForRank(rank) orelse break;
            fingerprint = fnv1aU32(fingerprint, rank);
            fingerprint = fnv1aU32(fingerprint, @as(u32, @intCast(token.len)));
            fingerprint = fnv1aBytes(fingerprint, token);
        }

        return fingerprint;
    }

    fn fnv1aBytes(initial_hash: u64, data: []const u8) u64 {
        var acc = initial_hash;
        for (data) |byte| {
            acc ^= @as(u64, byte);
            acc *%= 0x100000001b3;
        }
        return acc;
    }

    fn fnv1aU32(initial_hash: u64, value: u32) u64 {
        var value_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &value_bytes, value, .little);
        return fnv1aBytes(initial_hash, &value_bytes);
    }
};

comptime {
    if (!std.math.isPowerOfTwo(entry_count)) {
        @compileError("pair cache entry_count must be a power of two");
    }
}

test "pair cache stores and retrieves values" {
    var cache = PairCache.init();

    try std.testing.expect(cache.get(1, 2) == null);
    try std.testing.expect(cache.put(1, 2, 123));
    try std.testing.expectEqual(@as(?u32, 123), cache.get(1, 2));

    try std.testing.expect(cache.put(1, 2, 456));
    try std.testing.expectEqual(@as(?u32, 456), cache.get(1, 2));
}

test "pair cache clear resets entries" {
    var cache = PairCache.init();
    try std.testing.expect(cache.put(10, 11, 99));
    try std.testing.expectEqual(@as(?u32, 99), cache.get(10, 11));

    cache.clear();
    try std.testing.expect(cache.get(10, 11) == null);
    try std.testing.expectEqual(@as(usize, 0), cache.usedSlots());
}

test "pair cache can be seeded from rank table tokens" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\YWJi 3
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    var cache = PairCache.init();
    cache.populateFromRankTable(&table);
    try std.testing.expectEqual(@as(?u32, 2), cache.get(0, 1));
    try std.testing.expectEqual(@as(?u32, 3), cache.get(2, 1));
}

test "pair cache known seed metadata is present" {
    try std.testing.expect(generated_seeds.seed_sets.len > 0);
    inline for (generated_seeds.seed_sets) |seed_set| {
        try std.testing.expect(seed_set.pairs.len > 0);
    }
}

test "pair cache default hash mode follows target capability" {
    const actual = PairCache.defaultHashMode();
    if (comptime PairCache.aarch64_crc_supported) {
        try std.testing.expectEqual(PairCache.HashMode.crc32, actual);
        return;
    }
    if (comptime PairCache.x86_crc_supported) {
        try std.testing.expect(actual == .crc32 or actual == .rapidhash);
        return;
    }
    try std.testing.expectEqual(PairCache.HashMode.rapidhash, actual);
}

test "pair cache known seed matching is no-op for unknown tables" {
    const allocator = std.testing.allocator;
    const payload =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;
    var table = try rank_loader.loadFromBytes(allocator, payload);
    defer table.deinit();

    var cache = PairCache.init();
    try std.testing.expect(!cache.populateFromKnownSeedSets(&table));
    try std.testing.expectEqual(@as(usize, 0), cache.usedSlots());
}
