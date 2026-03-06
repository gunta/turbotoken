const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const x86_64 = @import("arch/x86_64.zig");
const wasm_arch = @import("arch/wasm.zig");
const ScalarBackend = @import("arch/generic.zig").ScalarBackend;
const hash = @import("hash.zig");
const rank_loader = @import("rank_loader.zig");
const pretokenizer = @import("pretokenizer.zig");
const trainer = @import("trainer.zig");

const rank_cache_allocator = if (builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32)
    std.heap.wasm_allocator
else if (builtin.os.tag == .freestanding)
    std.heap.page_allocator
else
    std.heap.c_allocator;

const RankTableCache = struct {
    hash: u64 = 0,
    payload: ?[]u8 = null,
    last_input_ptr: usize = 0,
    last_input_len: usize = 0,
    table: ?rank_loader.RankTable = null,
};

var rank_table_cache: RankTableCache = .{};

const BpeParallelMode = enum {
    auto,
    on,
    off,
};

var bpe_parallel_mode: BpeParallelMode = .auto;
var bpe_parallel_once = std.once(initBpeParallelMode);

fn runtimeAllocator() std.mem.Allocator {
    if (builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32) {
        return std.heap.wasm_allocator;
    }
    if (builtin.os.tag == .freestanding) {
        return std.heap.page_allocator;
    }
    return std.heap.c_allocator;
}

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

pub export fn turbotoken_clear_rank_table_cache() void {
    clearRankTableCache();
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

    const rank_hash = hash.bytes(rank_slice);

    if (rank_table_cache.payload) |payload| {
        if (rank_table_cache.hash == rank_hash and payload.len == input_len and std.mem.eql(u8, payload, rank_slice)) {
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

    rank_table_cache.hash = rank_hash;
    rank_table_cache.payload = payload_copy;
    rank_table_cache.last_input_ptr = input_ptr;
    rank_table_cache.last_input_len = input_len;
    rank_table_cache.table = table;
    return &(rank_table_cache.table.?);
}

fn isTruthyEnvValue(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on");
}

fn initBpeParallelMode() void {
    if (builtin.os.tag == .freestanding) {
        bpe_parallel_mode = .off;
        return;
    }

    const disable = std.process.getEnvVarOwned(std.heap.page_allocator, "TURBOTOKEN_NATIVE_BPE_PARALLEL_DISABLE") catch {
        const enable = std.process.getEnvVarOwned(std.heap.page_allocator, "TURBOTOKEN_NATIVE_BPE_PARALLEL_ENABLE") catch {
            bpe_parallel_mode = .auto;
            return;
        };
        defer std.heap.page_allocator.free(enable);
        bpe_parallel_mode = if (isTruthyEnvValue(enable)) .on else .auto;
        return;
    };
    defer std.heap.page_allocator.free(disable);
    if (isTruthyEnvValue(disable)) {
        bpe_parallel_mode = .off;
        return;
    }

    const enable = std.process.getEnvVarOwned(std.heap.page_allocator, "TURBOTOKEN_NATIVE_BPE_PARALLEL_ENABLE") catch {
        bpe_parallel_mode = .auto;
        return;
    };
    defer std.heap.page_allocator.free(enable);
    bpe_parallel_mode = if (isTruthyEnvValue(enable)) .on else .auto;
}

fn selectedBpeParallelMode() BpeParallelMode {
    bpe_parallel_once.call();
    return bpe_parallel_mode;
}

fn rangeTotalBytes(starts: []const u32, ends: []const u32) usize {
    var total: usize = 0;
    for (starts, ends) |start, end| {
        if (end < start) {
            continue;
        }
        total +|= @as(usize, @intCast(end - start));
    }
    return total;
}

fn chooseBpeWorkerCount(segment_count: usize, total_bytes: usize) usize {
    if (segment_count <= 1) {
        return 1;
    }
    if (comptime builtin.single_threaded or builtin.os.tag == .freestanding) {
        return 1;
    }

    const mode = selectedBpeParallelMode();
    if (mode == .off) {
        return 1;
    }

    if (mode == .auto) {
        if (total_bytes < 512 * 1024) {
            return 1;
        }
        if (segment_count < 64) {
            return 1;
        }
    }

    const cpu_count = @as(usize, std.Thread.getCpuCount() catch 1);
    if (cpu_count <= 1) {
        return 1;
    }

    var worker_count = @min(cpu_count, @as(usize, 16));
    if (mode == .auto) {
        const max_by_ranges = @max(@as(usize, 1), segment_count / 8);
        worker_count = @min(worker_count, max_by_ranges);
    }
    if (worker_count <= 1) {
        return 1;
    }
    return @min(worker_count, segment_count);
}

const CountRangesContext = struct {
    in_slice: []const u8,
    starts: []const u32,
    ends: []const u32,
    table: *const rank_loader.RankTable,
    counts: []usize,
    failed: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
};

const EncodeRangesContext = struct {
    in_slice: []const u8,
    starts: []const u32,
    ends: []const u32,
    table: *const rank_loader.RankTable,
    token_prefix: []const usize,
    out_tokens: []u32,
    failed: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
};

fn markWorkerFailed(flag: *std.atomic.Value(u8)) void {
    _ = flag.cmpxchgStrong(0, 1, .acq_rel, .acquire);
}

fn countRangesWorker(ctx: *CountRangesContext, begin: usize, end: usize) void {
    const allocator = runtimeAllocator();
    const backend = ScalarBackend.init();

    for (begin..end) |idx| {
        if (ctx.failed.load(.acquire) != 0) {
            return;
        }

        const start = @as(usize, @intCast(ctx.starts[idx]));
        const finish = @as(usize, @intCast(ctx.ends[idx]));
        if (finish < start or finish > ctx.in_slice.len) {
            markWorkerFailed(&ctx.failed);
            return;
        }

        const counted = backend.count(allocator, ctx.in_slice[start..finish], ctx.table) catch {
            markWorkerFailed(&ctx.failed);
            return;
        };
        ctx.counts[idx] = counted;
    }
}

fn encodeRangesWorker(ctx: *EncodeRangesContext, begin: usize, end: usize) void {
    const allocator = runtimeAllocator();
    const backend = ScalarBackend.init();

    for (begin..end) |idx| {
        if (ctx.failed.load(.acquire) != 0) {
            return;
        }

        const start = @as(usize, @intCast(ctx.starts[idx]));
        const finish = @as(usize, @intCast(ctx.ends[idx]));
        if (finish < start or finish > ctx.in_slice.len) {
            markWorkerFailed(&ctx.failed);
            return;
        }

        const out_start = ctx.token_prefix[idx];
        const out_end = ctx.token_prefix[idx + 1];
        if (out_end < out_start or out_end > ctx.out_tokens.len) {
            markWorkerFailed(&ctx.failed);
            return;
        }

        if (out_start == out_end) {
            continue;
        }

        const encoded = backend.encode(allocator, ctx.in_slice[start..finish], ctx.table) catch {
            markWorkerFailed(&ctx.failed);
            return;
        };
        defer allocator.free(encoded);

        if (encoded.len != out_end - out_start) {
            markWorkerFailed(&ctx.failed);
            return;
        }

        @memcpy(ctx.out_tokens[out_start..out_end], encoded);
    }
}

fn runCountRangesParallel(
    allocator: std.mem.Allocator,
    ctx: *CountRangesContext,
    worker_count: usize,
) bool {
    if (ctx.starts.len == 0) {
        return true;
    }
    if (worker_count <= 1 or comptime builtin.single_threaded or builtin.os.tag == .freestanding) {
        countRangesWorker(ctx, 0, ctx.starts.len);
        return ctx.failed.load(.acquire) == 0;
    }

    var threads = allocator.alloc(std.Thread, worker_count - 1) catch {
        countRangesWorker(ctx, 0, ctx.starts.len);
        return ctx.failed.load(.acquire) == 0;
    };
    defer allocator.free(threads);

    const chunk = (ctx.starts.len + worker_count - 1) / worker_count;
    var spawned: usize = 0;
    var worker_idx: usize = 1;
    while (worker_idx < worker_count) : (worker_idx += 1) {
        const begin = worker_idx * chunk;
        if (begin >= ctx.starts.len) {
            break;
        }
        const end = @min(ctx.starts.len, begin + chunk);
        threads[spawned] = std.Thread.spawn(.{}, countRangesWorker, .{ ctx, begin, end }) catch {
            for (threads[0..spawned]) |*thread| {
                thread.join();
            }
            ctx.failed.store(0, .release);
            countRangesWorker(ctx, 0, ctx.starts.len);
            return ctx.failed.load(.acquire) == 0;
        };
        spawned += 1;
    }

    countRangesWorker(ctx, 0, @min(ctx.starts.len, chunk));
    for (threads[0..spawned]) |*thread| {
        thread.join();
    }
    return ctx.failed.load(.acquire) == 0;
}

fn runEncodeRangesParallel(
    allocator: std.mem.Allocator,
    ctx: *EncodeRangesContext,
    worker_count: usize,
) bool {
    if (ctx.starts.len == 0) {
        return true;
    }
    if (worker_count <= 1 or comptime builtin.single_threaded or builtin.os.tag == .freestanding) {
        encodeRangesWorker(ctx, 0, ctx.starts.len);
        return ctx.failed.load(.acquire) == 0;
    }

    var threads = allocator.alloc(std.Thread, worker_count - 1) catch {
        encodeRangesWorker(ctx, 0, ctx.starts.len);
        return ctx.failed.load(.acquire) == 0;
    };
    defer allocator.free(threads);

    const chunk = (ctx.starts.len + worker_count - 1) / worker_count;
    var spawned: usize = 0;
    var worker_idx: usize = 1;
    while (worker_idx < worker_count) : (worker_idx += 1) {
        const begin = worker_idx * chunk;
        if (begin >= ctx.starts.len) {
            break;
        }
        const end = @min(ctx.starts.len, begin + chunk);
        threads[spawned] = std.Thread.spawn(.{}, encodeRangesWorker, .{ ctx, begin, end }) catch {
            for (threads[0..spawned]) |*thread| {
                thread.join();
            }
            ctx.failed.store(0, .release);
            encodeRangesWorker(ctx, 0, ctx.starts.len);
            return ctx.failed.load(.acquire) == 0;
        };
        spawned += 1;
    }

    encodeRangesWorker(ctx, 0, @min(ctx.starts.len, chunk));
    for (threads[0..spawned]) |*thread| {
        thread.join();
    }
    return ctx.failed.load(.acquire) == 0;
}

fn encodeBpeRangesFromTable(
    allocator: std.mem.Allocator,
    in_slice: []const u8,
    starts: []const u32,
    ends: []const u32,
    table: *const rank_loader.RankTable,
    out_tokens: [*c]u32,
    out_cap: usize,
    out_token_offsets: [*c]u32,
) isize {
    if (starts.len != ends.len) {
        return -1;
    }

    if (out_token_offsets != null) {
        out_token_offsets[0] = 0;
    }
    if (starts.len == 0) {
        return 0;
    }

    for (starts, ends) |start, finish| {
        if (finish < start or finish > in_slice.len) {
            return -1;
        }
    }

    const counts = allocator.alloc(usize, starts.len) catch return -1;
    defer allocator.free(counts);
    @memset(counts, 0);

    const total_bytes = rangeTotalBytes(starts, ends);
    const worker_count = chooseBpeWorkerCount(starts.len, total_bytes);
    var count_ctx = CountRangesContext{
        .in_slice = in_slice,
        .starts = starts,
        .ends = ends,
        .table = table,
        .counts = counts,
    };

    if (!runCountRangesParallel(allocator, &count_ctx, worker_count)) {
        return -1;
    }

    var token_prefix = allocator.alloc(usize, starts.len + 1) catch return -1;
    defer allocator.free(token_prefix);
    token_prefix[0] = 0;
    for (counts, 0..) |count, idx| {
        if (count > std.math.maxInt(usize) - token_prefix[idx]) {
            return -1;
        }
        const next = token_prefix[idx] + count;
        token_prefix[idx + 1] = next;
        if (out_token_offsets != null) {
            if (next > std.math.maxInt(u32)) {
                return -1;
            }
            out_token_offsets[idx + 1] = @as(u32, @intCast(next));
        }
    }

    const total_tokens = token_prefix[token_prefix.len - 1];
    if (out_tokens != null) {
        if (out_cap < total_tokens) {
            return -1;
        }

        var encode_ctx = EncodeRangesContext{
            .in_slice = in_slice,
            .starts = starts,
            .ends = ends,
            .table = table,
            .token_prefix = token_prefix,
            .out_tokens = out_tokens[0..total_tokens],
        };

        if (!runEncodeRangesParallel(allocator, &encode_ctx, worker_count)) {
            return -1;
        }
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
}

fn countBpeRangesFromTable(
    allocator: std.mem.Allocator,
    in_slice: []const u8,
    starts: []const u32,
    ends: []const u32,
    table: *const rank_loader.RankTable,
) !usize {
    if (starts.len != ends.len) {
        return error.InvalidInput;
    }

    for (starts, ends) |start, finish| {
        if (finish < start or finish > in_slice.len) {
            return error.InvalidInput;
        }
    }

    const counts = try allocator.alloc(usize, starts.len);
    defer allocator.free(counts);
    @memset(counts, 0);

    const total_bytes = rangeTotalBytes(starts, ends);
    const worker_count = chooseBpeWorkerCount(starts.len, total_bytes);
    var count_ctx = CountRangesContext{
        .in_slice = in_slice,
        .starts = starts,
        .ends = ends,
        .table = table,
        .counts = counts,
    };

    if (!runCountRangesParallel(allocator, &count_ctx, worker_count)) {
        return error.OutOfMemory;
    }

    var total_tokens: usize = 0;
    for (counts) |count| {
        if (count > std.math.maxInt(usize) - total_tokens) {
            return error.OutOfMemory;
        }
        total_tokens += count;
    }
    return total_tokens;
}

const PretokenizedRanges = struct {
    starts: []u32,
    ends: []u32,

    fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.starts);
        allocator.free(self.ends);
        self.* = .{ .starts = &.{}, .ends = &.{} };
    }
};

fn allocAsciiO200kRanges(allocator: std.mem.Allocator, in_slice: []const u8) !PretokenizedRanges {
    const range_count = try pretokenizer.splitAsciiO200kRanges(in_slice, null, null);

    const starts = try allocator.alloc(u32, range_count);
    errdefer allocator.free(starts);
    const ends = try allocator.alloc(u32, range_count);
    errdefer allocator.free(ends);

    const written = try pretokenizer.splitAsciiO200kRanges(in_slice, starts, ends);
    if (written != range_count) {
        return error.InvalidInput;
    }

    return .{
        .starts = starts,
        .ends = ends,
    };
}

pub export fn turbotoken_version() [*c]const u8 {
    return "0.1.0-dev";
}

pub export fn turbotoken_wasm_alloc(size: usize) [*c]u8 {
    if (size == 0) {
        return null;
    }
    const allocator = runtimeAllocator();
    const memory = allocator.alloc(u8, size) catch return null;
    return memory.ptr;
}

pub export fn turbotoken_wasm_free(ptr: [*c]u8, size: usize) void {
    if (ptr == null or size == 0) {
        return;
    }
    const allocator = runtimeAllocator();
    allocator.free(ptr[0..size]);
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

pub export fn turbotoken_pretokenize_ascii_o200k_ranges(
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
        const needed = pretokenizer.splitAsciiO200kRanges(in_slice, null, null) catch return -1;
        if (needed > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(needed));
    }

    const starts = out_starts[0..out_cap];
    const ends = out_ends[0..out_cap];
    const written = pretokenizer.splitAsciiO200kRanges(in_slice, starts, ends) catch return -1;
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
    else if (builtin.cpu.arch == .x86_64 and x86_64.available())
        x86_64.countNonAscii(in_slice)
    else if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable())
        wasm_arch.countNonAscii(in_slice)
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

pub export fn turbotoken_count_ascii_class_boundaries_utf8(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len <= 1) {
        return 0;
    }
    if (text == null) {
        return -1;
    }

    const count = pretokenizer.countAsciiClassBoundaries(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_ascii_class_boundaries_utf8_scalar(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len <= 1) {
        return 0;
    }
    if (text == null) {
        return -1;
    }

    const count = pretokenizer.countAsciiClassBoundariesScalar(text[0..text_len]);
    if (count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(count));
}

pub export fn turbotoken_count_ascii_class_boundaries_utf8_neon(
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (text_len <= 1) {
        return 0;
    }
    if (text == null) {
        return -1;
    }
    if (builtin.cpu.arch != .aarch64 or !aarch64.available()) {
        return -1;
    }

    const count = pretokenizer.countAsciiClassBoundariesNeon(text[0..text_len]);
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
    if (builtin.cpu.arch == .x86_64 and x86_64.available() and text_len >= 16) {
        x86_64.encodeU8ToU32(in_slice, out_slice);
        return @as(isize, @intCast(text_len));
    }
    if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable() and text_len >= 16) {
        wasm_arch.encodeU8ToU32(in_slice, out_slice);
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
    if (builtin.cpu.arch == .x86_64 and x86_64.decoderAvx2HookAvailable(token_len)) {
        if (!x86_64.validateAndDecodeU32ToU8Avx2(in_slice, out_slice)) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }
    if (builtin.cpu.arch == .x86_64 and x86_64.available() and token_len >= 4) {
        if (!x86_64.validateAndDecodeU32ToU8(in_slice, out_slice)) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }
    if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable() and token_len >= 16) {
        if (!wasm_arch.validateAndDecodeU32ToU8(in_slice, out_slice)) {
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

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];

    const backend = ScalarBackend.init();
    const tokens = backend.encode(allocator, in_slice, table) catch return -1;
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

pub export fn turbotoken_train_bpe_from_chunk_counts(
    chunks: [*c]const u8,
    chunks_len: usize,
    chunk_offsets: [*c]const u32,
    chunk_offsets_len: usize,
    chunk_counts: [*c]const u32,
    chunk_counts_len: usize,
    vocab_size: u32,
    min_frequency: u32,
    out_merges: [*c]u32,
    out_cap: usize,
) isize {
    if (chunk_offsets == null or chunk_counts == null) {
        return -1;
    }
    if (chunks_len > 0 and chunks == null) {
        return -1;
    }
    if (chunk_offsets_len == 0 or chunk_counts_len + 1 != chunk_offsets_len) {
        return -1;
    }
    if (vocab_size < 256 or min_frequency == 0) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const chunk_slice: []const u8 = if (chunks_len == 0) &[_]u8{} else chunks[0..chunks_len];
    const offsets = chunk_offsets[0..chunk_offsets_len];
    const counts = chunk_counts[0..chunk_counts_len];

    const merges = trainer.trainMergesFromChunkCounts(
        allocator,
        chunk_slice,
        offsets,
        counts,
        vocab_size,
        min_frequency,
    ) catch return -1;
    defer allocator.free(merges);

    if (out_merges == null) {
        if (merges.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(merges.len));
    }

    const needed_u32 = merges.len * 3;
    if (out_cap < needed_u32) {
        return -1;
    }

    var out_idx: usize = 0;
    for (merges) |merge| {
        out_merges[out_idx] = merge.left;
        out_merges[out_idx + 1] = merge.right;
        out_merges[out_idx + 2] = merge.new_id;
        out_idx += 3;
    }
    if (merges.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(merges.len));
}

const AsciiChunkEntry = struct {
    start: u32,
    end: u32,
    count: u32,
};

fn encodeMergeOutput(
    merges: []const trainer.Merge,
    out_merges: [*c]u32,
    out_cap: usize,
) isize {
    if (out_merges == null) {
        if (merges.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(merges.len));
    }

    const needed_u32 = merges.len * 3;
    if (out_cap < needed_u32) {
        return -1;
    }

    var out_idx: usize = 0;
    for (merges) |merge| {
        out_merges[out_idx] = merge.left;
        out_merges[out_idx + 1] = merge.right;
        out_merges[out_idx + 2] = merge.new_id;
        out_idx += 3;
    }
    if (merges.len > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(merges.len));
}

fn trainAsciiO200kFromTextSlices(
    allocator: std.mem.Allocator,
    all_text: []const u8,
    text_offsets: []const u32,
    vocab_size: u32,
    min_frequency: u32,
) ![]trainer.Merge {
    if (text_offsets.len == 0) {
        return error.InvalidInput;
    }
    if (text_offsets[0] != 0) {
        return error.InvalidInput;
    }
    if (text_offsets[text_offsets.len - 1] != all_text.len) {
        return error.InvalidInput;
    }

    var prev_offset: u32 = text_offsets[0];
    for (text_offsets[1..]) |next_offset| {
        if (next_offset < prev_offset or next_offset > all_text.len) {
            return error.InvalidInput;
        }
        prev_offset = next_offset;
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const work_allocator = arena_state.allocator();

    var chunk_index: std.StringHashMapUnmanaged(u32) = .{};
    var chunk_entries = std.ArrayListUnmanaged(AsciiChunkEntry){};
    const estimated_unique_chunks = @max(
        text_offsets.len - 1,
        @min(all_text.len / 4 + 1, @as(usize, 65_536)),
    );
    try chunk_index.ensureTotalCapacity(work_allocator, @as(u32, @intCast(estimated_unique_chunks)));
    try chunk_entries.ensureTotalCapacityPrecise(work_allocator, estimated_unique_chunks);

    for (0..text_offsets.len - 1) |text_idx| {
        const text_start = @as(usize, @intCast(text_offsets[text_idx]));
        const text_end = @as(usize, @intCast(text_offsets[text_idx + 1]));
        const text_slice = all_text[text_start..text_end];

        var local_idx: usize = 0;
        while (try pretokenizer.nextAsciiO200kRange(text_slice, &local_idx)) |range| {
            const abs_start = text_start + range.start;
            const abs_end = text_start + range.end;
            if (abs_end > std.math.maxInt(u32)) {
                return error.InvalidInput;
            }

            const piece = text_slice[range.start..range.end];
            const idx_entry = try chunk_index.getOrPut(work_allocator, piece);
            if (!idx_entry.found_existing) {
                idx_entry.value_ptr.* = @as(u32, @intCast(chunk_entries.items.len));
                try chunk_entries.append(work_allocator, .{
                    .start = @as(u32, @intCast(abs_start)),
                    .end = @as(u32, @intCast(abs_end)),
                    .count = 1,
                });
            } else {
                const entry_idx = @as(usize, @intCast(idx_entry.value_ptr.*));
                const current = chunk_entries.items[entry_idx].count;
                const next = current + 1;
                if (next < current) {
                    return error.InvalidInput;
                }
                chunk_entries.items[entry_idx].count = next;
            }
        }
    }

    var flat_chunks = std.ArrayListUnmanaged(u8){};
    try flat_chunks.ensureTotalCapacity(work_allocator, all_text.len);
    const offsets = try work_allocator.alloc(u32, chunk_entries.items.len + 1);
    const counts = try work_allocator.alloc(u32, chunk_entries.items.len);

    offsets[0] = 0;
    for (chunk_entries.items, 0..) |entry, idx| {
        const start_usize = @as(usize, @intCast(entry.start));
        const end_usize = @as(usize, @intCast(entry.end));
        try flat_chunks.appendSlice(work_allocator, all_text[start_usize..end_usize]);
        if (flat_chunks.items.len > std.math.maxInt(u32)) {
            return error.InvalidInput;
        }
        offsets[idx + 1] = @as(u32, @intCast(flat_chunks.items.len));
        counts[idx] = entry.count;
    }

    return trainer.trainMergesFromChunkCounts(
        allocator,
        flat_chunks.items,
        offsets,
        counts,
        vocab_size,
        min_frequency,
    );
}

pub export fn turbotoken_train_bpe_ascii_o200k(
    text: [*c]const u8,
    text_len: usize,
    vocab_size: u32,
    min_frequency: u32,
    out_merges: [*c]u32,
    out_cap: usize,
) isize {
    if (text_len > 0 and text == null) {
        return -1;
    }
    if (vocab_size < 256 or min_frequency == 0) {
        return -1;
    }
    if (text_len > std.math.maxInt(u32)) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    const offsets = [_]u32{ 0, @as(u32, @intCast(text_len)) };

    const merges = trainAsciiO200kFromTextSlices(
        allocator,
        in_slice,
        &offsets,
        vocab_size,
        min_frequency,
    ) catch return -1;
    defer allocator.free(merges);

    return encodeMergeOutput(merges, out_merges, out_cap);
}

pub export fn turbotoken_train_bpe_ascii_o200k_multi(
    texts: [*c]const u8,
    texts_len: usize,
    text_offsets: [*c]const u32,
    text_offsets_len: usize,
    vocab_size: u32,
    min_frequency: u32,
    out_merges: [*c]u32,
    out_cap: usize,
) isize {
    if (text_offsets == null) {
        return -1;
    }
    if (texts_len > 0 and texts == null) {
        return -1;
    }
    if (text_offsets_len == 0) {
        return -1;
    }
    if (vocab_size < 256 or min_frequency == 0) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const all_text: []const u8 = if (texts_len == 0) &[_]u8{} else texts[0..texts_len];
    const offsets = text_offsets[0..text_offsets_len];

    const merges = trainAsciiO200kFromTextSlices(
        allocator,
        all_text,
        offsets,
        vocab_size,
        min_frequency,
    ) catch return -1;
    defer allocator.free(merges);

    return encodeMergeOutput(merges, out_merges, out_cap);
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
    const starts = offset_slice[0..segment_count];
    const ends = offset_slice[1..offsets_len];

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    return encodeBpeRangesFromTable(
        allocator,
        in_slice,
        starts,
        ends,
        table,
        out_tokens,
        out_cap,
        out_token_offsets,
    );
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

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    return encodeBpeRangesFromTable(
        allocator,
        in_slice,
        starts,
        ends,
        table,
        out_tokens,
        out_cap,
        out_token_offsets,
    );
}

pub export fn turbotoken_count_bpe_ranges_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    range_starts: [*c]const u32,
    range_ends: [*c]const u32,
    ranges_len: usize,
) isize {
    if (rank_bytes == null or range_starts == null or range_ends == null) {
        return -1;
    }
    if (text_len > 0 and text == null) {
        return -1;
    }

    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    const starts = range_starts[0..ranges_len];
    const ends = range_ends[0..ranges_len];

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const total_tokens = countBpeRangesFromTable(allocator, in_slice, starts, ends, table) catch return -1;
    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
}

pub export fn turbotoken_bpe_ranges_token_layout_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    input_len: usize,
    range_starts: [*c]const u32,
    range_ends: [*c]const u32,
    ranges_len: usize,
    tokens: [*c]const u32,
    token_len: usize,
    token_offsets: [*c]const u32,
    token_offsets_len: usize,
    source_chunk_base: u32,
    chunk_bytes: u32,
    num_chunks: u32,
    out_token_starts: [*c]u32,
    out_source_chunks: [*c]u32,
    out_cap: usize,
) isize {
    if (rank_bytes == null or range_starts == null or range_ends == null or token_offsets == null) {
        return -1;
    }
    if (chunk_bytes == 0 or num_chunks == 0) {
        return -1;
    }
    if (token_offsets_len != ranges_len + 1) {
        return -1;
    }
    if (token_len > 0 and tokens == null) {
        return -1;
    }

    if (out_token_starts == null or out_source_chunks == null or out_cap == 0) {
        if (token_len > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(token_len));
    }
    if (out_cap < token_len) {
        return -1;
    }

    const starts = range_starts[0..ranges_len];
    const ends = range_ends[0..ranges_len];
    const offsets = token_offsets[0..token_offsets_len];
    const token_slice: []const u32 = if (token_len == 0) &[_]u32{} else tokens[0..token_len];
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;

    if (offsets[0] != 0) {
        return -1;
    }
    if (offsets[offsets.len - 1] != token_len) {
        return -1;
    }
    var prev_offset = offsets[0];
    for (offsets[1..]) |next_offset| {
        if (next_offset < prev_offset or next_offset > token_len) {
            return -1;
        }
        prev_offset = next_offset;
    }

    var written: usize = 0;
    for (0..ranges_len) |idx| {
        const ext_start = starts[idx];
        const ext_end = ends[idx];
        if (ext_start > ext_end or ext_end > input_len) {
            return -1;
        }
        const ext_len = ext_end - ext_start;
        const token_start = offsets[idx];
        const token_end = offsets[idx + 1];
        if (token_end < token_start or token_end > token_len) {
            return -1;
        }

        const source_chunk = source_chunk_base + @as(u32, @intCast(idx));
        if (source_chunk >= num_chunks) {
            return -1;
        }

        var cursor: usize = 0;
        for (token_start..token_end) |token_idx| {
            const token = token_slice[token_idx];
            const token_bytes = table.tokenForRank(token) orelse return -1;
            const token_bytes_len = token_bytes.len;
            if (token_bytes_len > ext_len -| cursor) {
                return -1;
            }

            const global_start = @as(usize, ext_start) + cursor;
            if (global_start > std.math.maxInt(u32)) {
                return -1;
            }
            out_token_starts[written] = @as(u32, @intCast(global_start));
            out_source_chunks[written] = source_chunk;
            written += 1;
            cursor += token_bytes_len;
        }
        if (cursor != ext_len) {
            return -1;
        }
    }

    if (written != token_len) {
        return -1;
    }
    if (written > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(written));
}

pub export fn turbotoken_filter_tokens_by_keep_flags(
    tokens: [*c]const u32,
    keep_flags: [*c]const u32,
    token_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (token_len > 0 and (tokens == null or keep_flags == null)) {
        return -1;
    }

    const token_slice: []const u32 = if (token_len == 0) &[_]u32{} else tokens[0..token_len];
    const flag_slice: []const u32 = if (token_len == 0) &[_]u32{} else keep_flags[0..token_len];

    var needed: usize = 0;
    for (flag_slice) |flag| {
        if (flag != 0) {
            needed += 1;
        }
    }

    if (needed > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }

    if (out_tokens == null or out_cap == 0) {
        return @as(isize, @intCast(needed));
    }
    if (out_cap < needed) {
        return -1;
    }

    var written: usize = 0;
    for (token_slice, flag_slice) |token, flag| {
        if (flag != 0) {
            out_tokens[written] = token;
            written += 1;
        }
    }
    if (written != needed) {
        return -1;
    }
    return @as(isize, @intCast(written));
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
    const allocator = runtimeAllocator();

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

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];

    const backend = ScalarBackend.init();
    const token_count = backend.count(allocator, in_slice, table) catch return -1;
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

pub export fn turbotoken_is_within_token_limit_bpe_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
    token_limit: usize,
) isize {
    if (rank_bytes == null or text == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];

    const backend = ScalarBackend.init();
    const token_count = backend.count(allocator, in_slice, table) catch return -1;
    if (token_count > token_limit) {
        return -2;
    }
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

fn readFileAllocFromPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (builtin.os.tag == .freestanding) {
        return error.Unsupported;
    }
    if (path.len == 0 or std.mem.indexOfScalar(u8, path, 0) != null) {
        return error.InvalidInput;
    }
    return std.fs.cwd().readFileAlloc(allocator, path, std.math.maxInt(usize));
}

pub export fn turbotoken_encode_bpe_file_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    file_path: [*c]const u8,
    file_path_len: usize,
    out_tokens: [*c]u32,
    out_cap: usize,
) isize {
    if (rank_bytes == null or file_path == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const path_slice = file_path[0..file_path_len];
    const file_bytes = readFileAllocFromPath(allocator, path_slice) catch return -1;
    defer allocator.free(file_bytes);

    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();
    const tokens = backend.encode(allocator, file_bytes, table) catch return -1;
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

pub export fn turbotoken_count_bpe_file_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    file_path: [*c]const u8,
    file_path_len: usize,
) isize {
    if (rank_bytes == null or file_path == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const path_slice = file_path[0..file_path_len];
    const file_bytes = readFileAllocFromPath(allocator, path_slice) catch return -1;
    defer allocator.free(file_bytes);

    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();
    const token_count = backend.count(allocator, file_bytes, table) catch return -1;
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

pub export fn turbotoken_is_within_token_limit_bpe_file_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    file_path: [*c]const u8,
    file_path_len: usize,
    token_limit: usize,
) isize {
    if (rank_bytes == null or file_path == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const path_slice = file_path[0..file_path_len];
    const file_bytes = readFileAllocFromPath(allocator, path_slice) catch return -1;
    defer allocator.free(file_bytes);

    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const backend = ScalarBackend.init();
    const token_count = backend.count(allocator, file_bytes, table) catch return -1;
    if (token_count > token_limit) {
        return -2;
    }
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

const AsciiO200kCountCacheEntry = struct {
    count: usize,
};

const AsciiO200kEncodeCacheEntry = struct {
    tokens: []u32,
};

const AsciiO200kSmallCountCacheEntry = struct {
    piece: []const u8,
    count: usize,
};

const AsciiO200kSmallEncodeCacheEntry = struct {
    piece: []const u8,
    tokens: []u32,
};

const ascii_o200k_small_cache_cap: usize = 64;
const ascii_o200k_piece_cache_cap: usize = 65_536;
const ascii_letter_space_piece_cache_cap: usize = 65_536;

fn countBpeAsciiO200kFromTable(
    allocator: std.mem.Allocator,
    backend: *const ScalarBackend,
    in_slice: []const u8,
    table: *const rank_loader.RankTable,
) !usize {
    var small_cache: [ascii_o200k_small_cache_cap]AsciiO200kSmallCountCacheEntry = undefined;
    var small_cache_len: usize = 0;
    var piece_cache: std.StringHashMapUnmanaged(AsciiO200kCountCacheEntry) = .{};
    defer piece_cache.deinit(allocator);

    var idx: usize = 0;
    var total_count: usize = 0;
    while (try pretokenizer.nextAsciiO200kRange(in_slice, &idx)) |range| {
        const piece = in_slice[range.start..range.end];
        var handled = false;
        var small_idx: usize = 0;
        while (small_idx < small_cache_len) : (small_idx += 1) {
            const cached = small_cache[small_idx];
            if (cached.piece.len == piece.len and std.mem.eql(u8, cached.piece, piece)) {
                total_count += cached.count;
                handled = true;
                break;
            }
        }
        if (handled) {
            continue;
        }

        if (small_cache_len >= ascii_o200k_small_cache_cap) {
            if (piece_cache.get(piece)) |cached| {
                total_count += cached.count;
                continue;
            }
        }

        const piece_count = try backend.count(allocator, piece, table);
        total_count += piece_count;

        if (small_cache_len < ascii_o200k_small_cache_cap) {
            small_cache[small_cache_len] = .{
                .piece = piece,
                .count = piece_count,
            };
            small_cache_len += 1;
            continue;
        }

        if (piece_cache.count() >= ascii_o200k_piece_cache_cap) {
            continue;
        }

        try piece_cache.put(allocator, piece, .{ .count = piece_count });
    }

    return total_count;
}

fn encodeBpeAsciiO200kFromTable(
    allocator: std.mem.Allocator,
    backend: *const ScalarBackend,
    in_slice: []const u8,
    table: *const rank_loader.RankTable,
    out_tokens: [*c]u32,
    out_cap: usize,
) !isize {
    var small_cache: [ascii_o200k_small_cache_cap]AsciiO200kSmallEncodeCacheEntry = undefined;
    var small_cache_len: usize = 0;
    defer {
        for (small_cache[0..small_cache_len]) |entry| {
            allocator.free(entry.tokens);
        }
    }

    var piece_cache: std.StringHashMapUnmanaged(AsciiO200kEncodeCacheEntry) = .{};
    defer {
        var it = piece_cache.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.tokens);
        }
        piece_cache.deinit(allocator);
    }

    var idx: usize = 0;
    var total_tokens: usize = 0;
    while (try pretokenizer.nextAsciiO200kRange(in_slice, &idx)) |range| {
        const piece = in_slice[range.start..range.end];

        var handled = false;
        var small_idx: usize = 0;
        while (small_idx < small_cache_len) : (small_idx += 1) {
            const cached = small_cache[small_idx];
            if (cached.piece.len == piece.len and std.mem.eql(u8, cached.piece, piece)) {
                if (cached.tokens.len > out_cap -| total_tokens) {
                    return error.OutOfMemory;
                }
                @memcpy(out_tokens[total_tokens .. total_tokens + cached.tokens.len], cached.tokens);
                total_tokens += cached.tokens.len;
                handled = true;
                break;
            }
        }
        if (handled) {
            continue;
        }

        if (small_cache_len >= ascii_o200k_small_cache_cap) {
            if (piece_cache.get(piece)) |cached| {
                if (cached.tokens.len > out_cap -| total_tokens) {
                    return error.OutOfMemory;
                }
                @memcpy(out_tokens[total_tokens .. total_tokens + cached.tokens.len], cached.tokens);
                total_tokens += cached.tokens.len;
                continue;
            }
        }

        const encoded = try backend.encode(allocator, piece, table);
        defer allocator.free(encoded);
        if (encoded.len > out_cap -| total_tokens) {
            return error.OutOfMemory;
        }
        @memcpy(out_tokens[total_tokens .. total_tokens + encoded.len], encoded);
        total_tokens += encoded.len;

        const token_copy = try allocator.alloc(u32, encoded.len);
        errdefer allocator.free(token_copy);
        @memcpy(token_copy, encoded);

        if (small_cache_len < ascii_o200k_small_cache_cap) {
            small_cache[small_cache_len] = .{
                .piece = piece,
                .tokens = token_copy,
            };
            small_cache_len += 1;
            continue;
        }

        if (piece_cache.count() < ascii_o200k_piece_cache_cap) {
            try piece_cache.put(allocator, piece, .{ .tokens = token_copy });
            continue;
        }

        allocator.free(token_copy);
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return error.OutOfMemory;
    }
    return @as(isize, @intCast(total_tokens));
}

pub export fn turbotoken_count_bpe_ascii_o200k_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (rank_bytes == null or text == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];
    const backend = ScalarBackend.init();

    const token_count = countBpeAsciiO200kFromTable(allocator, &backend, in_slice, table) catch return -1;
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

fn countBpeAsciiLetterSpaceFromTable(
    allocator: std.mem.Allocator,
    backend: *const ScalarBackend,
    in_slice: []const u8,
    table: *const rank_loader.RankTable,
) !usize {
    var piece_cache: std.StringHashMapUnmanaged(AsciiO200kCountCacheEntry) = .{};
    defer piece_cache.deinit(allocator);

    var idx: usize = 0;
    var total_count: usize = 0;
    while (try pretokenizer.nextAsciiLetterSpaceRange(in_slice, &idx)) |range| {
        const piece = in_slice[range.start..range.end];
        if (piece_cache.get(piece)) |cached| {
            total_count += cached.count;
            continue;
        }

        const piece_count = try backend.count(allocator, piece, table);
        total_count += piece_count;

        if (piece_cache.count() >= ascii_letter_space_piece_cache_cap) {
            continue;
        }

        try piece_cache.put(allocator, piece, .{ .count = piece_count });
    }

    return total_count;
}

pub export fn turbotoken_count_bpe_ascii_letter_space_from_ranks(
    rank_bytes: [*c]const u8,
    rank_len: usize,
    text: [*c]const u8,
    text_len: usize,
) isize {
    if (rank_bytes == null or text == null) {
        return -1;
    }

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];
    const backend = ScalarBackend.init();

    const token_count = countBpeAsciiLetterSpaceFromTable(allocator, &backend, in_slice, table) catch return -1;
    if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(token_count));
}

pub export fn turbotoken_encode_bpe_ascii_letter_space_from_ranks(
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

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];
    const backend = ScalarBackend.init();

    if (out_tokens == null) {
        const token_count = countBpeAsciiLetterSpaceFromTable(allocator, &backend, in_slice, table) catch return -1;
        if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(token_count));
    }

    var piece_cache: std.StringHashMapUnmanaged(AsciiO200kEncodeCacheEntry) = .{};
    defer {
        var it = piece_cache.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.tokens);
        }
        piece_cache.deinit(allocator);
    }

    var idx: usize = 0;
    var total_tokens: usize = 0;
    while ((pretokenizer.nextAsciiLetterSpaceRange(in_slice, &idx) catch return -1)) |range| {
        const piece = in_slice[range.start..range.end];

        if (piece_cache.get(piece)) |cached| {
            if (cached.tokens.len > out_cap -| total_tokens) {
                return -1;
            }
            @memcpy(out_tokens[total_tokens .. total_tokens + cached.tokens.len], cached.tokens);
            total_tokens += cached.tokens.len;
            continue;
        }

        const encoded = backend.encode(allocator, piece, table) catch return -1;
        defer allocator.free(encoded);
        if (encoded.len > out_cap -| total_tokens) {
            return -1;
        }
        @memcpy(out_tokens[total_tokens .. total_tokens + encoded.len], encoded);
        total_tokens += encoded.len;

        if (piece_cache.count() < ascii_letter_space_piece_cache_cap) {
            const token_copy = allocator.alloc(u32, encoded.len) catch return -1;
            errdefer allocator.free(token_copy);
            @memcpy(token_copy, encoded);
            piece_cache.put(allocator, piece, .{ .tokens = token_copy }) catch return -1;
        }
    }

    if (total_tokens > @as(usize, @intCast(std.math.maxInt(isize)))) {
        return -1;
    }
    return @as(isize, @intCast(total_tokens));
}

pub export fn turbotoken_encode_bpe_ascii_o200k_from_ranks(
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

    const allocator = runtimeAllocator();
    const rank_slice = rank_bytes[0..rank_len];
    const table = ensureCachedRankTable(rank_slice) catch return -1;
    const in_slice = text[0..text_len];
    const backend = ScalarBackend.init();

    if (out_tokens == null) {
        const token_count = countBpeAsciiO200kFromTable(allocator, &backend, in_slice, table) catch return -1;
        if (token_count > @as(usize, @intCast(std.math.maxInt(isize)))) {
            return -1;
        }
        return @as(isize, @intCast(token_count));
    }
    return encodeBpeAsciiO200kFromTable(allocator, &backend, in_slice, table, out_tokens, out_cap) catch return -1;
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

    const allocator = runtimeAllocator();
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

test "ascii o200k pretokenizer export returns ranges" {
    const text = "Tokenizer matters, for coding agents.\n";
    const needed = turbotoken_pretokenize_ascii_o200k_ranges(text.ptr, text.len, null, null, 0);
    try std.testing.expectEqual(@as(isize, 7), needed);

    var starts: [7]u32 = undefined;
    var ends: [7]u32 = undefined;
    const written = turbotoken_pretokenize_ascii_o200k_ranges(text.ptr, text.len, &starts, &ends, starts.len);
    try std.testing.expectEqual(@as(isize, 7), written);
    try std.testing.expectEqualSlices(u8, "Tokenizer", text[starts[0]..ends[0]]);
    try std.testing.expectEqualSlices(u8, " matters", text[starts[1]..ends[1]]);
    try std.testing.expectEqualSlices(u8, ",", text[starts[2]..ends[2]]);
    try std.testing.expectEqualSlices(u8, " for", text[starts[3]..ends[3]]);
    try std.testing.expectEqualSlices(u8, " coding", text[starts[4]..ends[4]]);
    try std.testing.expectEqualSlices(u8, " agents", text[starts[5]..ends[5]]);
    try std.testing.expectEqualSlices(u8, ".\n", text[starts[6]..ends[6]]);
}

test "ascii o200k direct training export learns repeated pair" {
    const text = "abababab";
    const needed = turbotoken_train_bpe_ascii_o200k(
        text.ptr,
        text.len,
        257,
        1,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 1), needed);

    var out: [3]u32 = undefined;
    const written = turbotoken_train_bpe_ascii_o200k(
        text.ptr,
        text.len,
        257,
        1,
        &out,
        out.len,
    );
    try std.testing.expectEqual(@as(isize, 1), written);
    try std.testing.expectEqual(@as(u32, 97), out[0]);
    try std.testing.expectEqual(@as(u32, 98), out[1]);
    try std.testing.expectEqual(@as(u32, 256), out[2]);
}

test "ascii o200k direct training multi export learns repeated pair" {
    const texts = "ab" ++ "ab";
    const offsets = [_]u32{ 0, 2, 4 };

    const needed = turbotoken_train_bpe_ascii_o200k_multi(
        texts.ptr,
        texts.len,
        &offsets,
        offsets.len,
        257,
        1,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 1), needed);

    var out: [3]u32 = undefined;
    const written = turbotoken_train_bpe_ascii_o200k_multi(
        texts.ptr,
        texts.len,
        &offsets,
        offsets.len,
        257,
        1,
        &out,
        out.len,
    );
    try std.testing.expectEqual(@as(isize, 1), written);
    try std.testing.expectEqual(@as(u32, 97), out[0]);
    try std.testing.expectEqual(@as(u32, 98), out[1]);
    try std.testing.expectEqual(@as(u32, 256), out[2]);
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

test "ascii class boundary exports agree with scalar baseline" {
    const text = "hello 123!! world\tz";
    const expected = pretokenizer.countAsciiClassBoundariesScalar(text);

    try std.testing.expectEqual(
        @as(isize, @intCast(expected)),
        turbotoken_count_ascii_class_boundaries_utf8(text.ptr, text.len),
    );
    try std.testing.expectEqual(
        @as(isize, @intCast(expected)),
        turbotoken_count_ascii_class_boundaries_utf8_scalar(text.ptr, text.len),
    );

    if (builtin.cpu.arch == .aarch64 and aarch64.available()) {
        try std.testing.expectEqual(
            @as(isize, @intCast(expected)),
            turbotoken_count_ascii_class_boundaries_utf8_neon(text.ptr, text.len),
        );
    } else {
        try std.testing.expectEqual(
            @as(isize, -1),
            turbotoken_count_ascii_class_boundaries_utf8_neon(text.ptr, text.len),
        );
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

    const within_limit = turbotoken_is_within_token_limit_bpe_from_ranks(
        ranks.ptr,
        ranks.len,
        "abb".ptr,
        3,
        2,
    );
    try std.testing.expectEqual(@as(isize, 2), within_limit);
    const over_limit = turbotoken_is_within_token_limit_bpe_from_ranks(
        ranks.ptr,
        ranks.len,
        "abb".ptr,
        3,
        1,
    );
    try std.testing.expectEqual(@as(isize, -2), over_limit);

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

test "file-path bpe exports encode/count/token-limit using provided ranks" {
    if (builtin.os.tag == .freestanding) {
        return;
    }

    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{
        .sub_path = "sample.txt",
        .data = "abb",
    });

    const allocator = std.testing.allocator;
    const root_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(root_path);
    const file_path = try std.fs.path.join(allocator, &.{ root_path, "sample.txt" });
    defer allocator.free(file_path);

    const needed = turbotoken_encode_bpe_file_from_ranks(
        ranks.ptr,
        ranks.len,
        file_path.ptr,
        file_path.len,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 2), needed);

    const counted = turbotoken_count_bpe_file_from_ranks(
        ranks.ptr,
        ranks.len,
        file_path.ptr,
        file_path.len,
    );
    try std.testing.expectEqual(@as(isize, 2), counted);

    const within = turbotoken_is_within_token_limit_bpe_file_from_ranks(
        ranks.ptr,
        ranks.len,
        file_path.ptr,
        file_path.len,
        2,
    );
    try std.testing.expectEqual(@as(isize, 2), within);

    const over = turbotoken_is_within_token_limit_bpe_file_from_ranks(
        ranks.ptr,
        ranks.len,
        file_path.ptr,
        file_path.len,
        1,
    );
    try std.testing.expectEqual(@as(isize, -2), over);

    var tokens: [2]u32 = undefined;
    const written = turbotoken_encode_bpe_file_from_ranks(
        ranks.ptr,
        ranks.len,
        file_path.ptr,
        file_path.len,
        &tokens,
        tokens.len,
    );
    try std.testing.expectEqual(@as(isize, 2), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1 }, &tokens);
}

test "ascii o200k full-text bpe exports match expected merges" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\IA== 3
        \\
    ;
    const text = "abb abb";

    const counted = turbotoken_count_bpe_ascii_o200k_from_ranks(ranks.ptr, ranks.len, text.ptr, text.len);
    try std.testing.expectEqual(@as(isize, 5), counted);

    const needed = turbotoken_encode_bpe_ascii_o200k_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 5), needed);

    var tokens: [5]u32 = undefined;
    const written = turbotoken_encode_bpe_ascii_o200k_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &tokens,
        tokens.len,
    );
    try std.testing.expectEqual(@as(isize, 5), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 1, 3, 2, 1 }, &tokens);
}

test "ascii letter-space full-text bpe exports match expected merges" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\IA== 3
        \\
    ;
    const text = "ab ab";

    const counted = turbotoken_count_bpe_ascii_letter_space_from_ranks(ranks.ptr, ranks.len, text.ptr, text.len);
    try std.testing.expectEqual(@as(isize, 3), counted);

    const needed = turbotoken_encode_bpe_ascii_letter_space_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 3), needed);

    var tokens: [3]u32 = undefined;
    const written = turbotoken_encode_bpe_ascii_letter_space_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &tokens,
        tokens.len,
    );
    try std.testing.expectEqual(@as(isize, 3), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 3, 2 }, &tokens);
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

test "range bpe encode from ranks supports count-only mode" {
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

    const needed = turbotoken_encode_bpe_ranges_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &starts,
        &ends,
        starts.len,
        null,
        0,
        &token_offsets,
        token_offsets.len,
    );
    try std.testing.expectEqual(@as(isize, 4), needed);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 4 }, &token_offsets);
}

test "range bpe count export returns total tokens" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const text = "abbabb";
    const starts = [_]u32{ 0, 0 };
    const ends = [_]u32{ 3, 3 };

    const counted = turbotoken_count_bpe_ranges_from_ranks(
        ranks.ptr,
        ranks.len,
        text.ptr,
        text.len,
        &starts,
        &ends,
        starts.len,
    );
    try std.testing.expectEqual(@as(isize, 4), counted);
}

test "range bpe token layout export returns token starts and source chunks" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;

    const text = "ababab";
    const starts = [_]u32{ 0, 2 };
    const ends = [_]u32{ 4, 6 };

    var token_offsets: [3]u32 = undefined;
    var tokens: [8]u32 = undefined;
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
    try std.testing.expectEqualSlices(u32, &[_]u32{ 2, 2, 2, 2 }, tokens[0..4]);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 4 }, &token_offsets);

    const needed = turbotoken_bpe_ranges_token_layout_from_ranks(
        ranks.ptr,
        ranks.len,
        text.len,
        &starts,
        &ends,
        starts.len,
        &tokens,
        4,
        &token_offsets,
        token_offsets.len,
        5,
        4,
        16,
        null,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 4), needed);

    var out_starts: [4]u32 = undefined;
    var out_source_chunks: [4]u32 = undefined;
    const layout_written = turbotoken_bpe_ranges_token_layout_from_ranks(
        ranks.ptr,
        ranks.len,
        text.len,
        &starts,
        &ends,
        starts.len,
        &tokens,
        4,
        &token_offsets,
        token_offsets.len,
        5,
        4,
        16,
        &out_starts,
        &out_source_chunks,
        4,
    );
    try std.testing.expectEqual(@as(isize, 4), layout_written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 0, 2, 2, 4 }, &out_starts);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 5, 5, 6, 6 }, &out_source_chunks);
}

test "filter tokens export compacts by keep flags" {
    const tokens = [_]u32{ 11, 22, 33, 44, 55 };
    const flags = [_]u32{ 1, 0, 1, 0, 1 };

    const needed = turbotoken_filter_tokens_by_keep_flags(
        &tokens,
        &flags,
        tokens.len,
        null,
        0,
    );
    try std.testing.expectEqual(@as(isize, 3), needed);

    var out: [3]u32 = undefined;
    const written = turbotoken_filter_tokens_by_keep_flags(
        &tokens,
        &flags,
        tokens.len,
        &out,
        out.len,
    );
    try std.testing.expectEqual(@as(isize, 3), written);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 11, 33, 55 }, &out);
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

test "clear rank-table cache export drops cached table state" {
    const ranks =
        \\YQ== 0
        \\Yg== 1
        \\YWI= 2
        \\
    ;
    _ = try ensureCachedRankTable(ranks);
    try std.testing.expect(rank_table_cache.table != null);
    turbotoken_clear_rank_table_cache();
    try std.testing.expect(rank_table_cache.table == null);
    try std.testing.expect(rank_table_cache.payload == null);
    try std.testing.expectEqual(@as(usize, 0), rank_table_cache.last_input_ptr);
    try std.testing.expectEqual(@as(usize, 0), rank_table_cache.last_input_len);
}
