const std = @import("std");
const rank_loader = @import("rank_loader.zig");
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
        for (table.entries.items) |entry| {
            if (entry.token.len < 2) {
                continue;
            }

            var split_at: usize = 1;
            while (split_at < entry.token.len) : (split_at += 1) {
                const left = table.get(entry.token[0..split_at]) orelse continue;
                const right = table.get(entry.token[split_at..]) orelse continue;
                _ = self.put(left, right, entry.rank);
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
        const hash = std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        return @as(usize, @truncate(hash)) & (entry_count - 1);
    }

    fn rankTableFingerprint(table: *const rank_loader.RankTable, limit: u32) u64 {
        var hash: u64 = 0xcbf29ce484222325;
        var rank: u32 = 0;

        while (rank < limit) : (rank += 1) {
            const token = table.tokenForRank(rank) orelse break;
            hash = fnv1aU32(hash, rank);
            hash = fnv1aU32(hash, @as(u32, @intCast(token.len)));
            hash = fnv1aBytes(hash, token);
        }

        return hash;
    }

    fn fnv1aBytes(initial_hash: u64, data: []const u8) u64 {
        var hash = initial_hash;
        for (data) |byte| {
            hash ^= @as(u64, byte);
            hash *%= 0x100000001b3;
        }
        return hash;
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
