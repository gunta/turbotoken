const std = @import("std");

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

    pub fn usedSlots(self: *const PairCache) usize {
        var used: usize = 0;
        for (self.entries) |entry| {
            if (entry.key != empty_key) {
                used += 1;
            }
        }
        return used;
    }

    fn packPair(left: u32, right: u32) u64 {
        return (@as(u64, left) << 32) | @as(u64, right);
    }

    fn slotIndex(key: u64) usize {
        const hash = std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
        return @as(usize, @truncate(hash)) & (entry_count - 1);
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
