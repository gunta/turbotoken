const builtin = @import("builtin");
const std = @import("std");

pub const CountKernel = enum(u32) {
    scalar = 0,
    sse42 = 1,
    avx2 = 2,
    avx512 = 3,
};

var selected_count_kernel: CountKernel = .scalar;
var count_kernel_once = std.once(initCountKernel);

fn hasFeature(feature: std.Target.x86.Feature) bool {
    return builtin.cpu.arch == .x86_64 and
        std.Target.x86.featureSetHas(builtin.cpu.features, feature);
}

pub fn available() bool {
    return builtin.cpu.arch == .x86_64;
}

pub fn sse42Available() bool {
    return hasFeature(.sse4_2);
}

pub fn avx2Available() bool {
    return hasFeature(.avx2);
}

pub fn avx512Available() bool {
    return hasFeature(.avx512f);
}

fn initCountKernel() void {
    selected_count_kernel = if (avx512Available())
        .avx512
    else if (avx2Available())
        .avx2
    else if (sse42Available())
        .sse42
    else
        .scalar;
}

pub fn selectedCountKernel() CountKernel {
    count_kernel_once.call();
    return selected_count_kernel;
}

// AVX2 hook used by pretokenizer boundary counting.
pub fn pretokenizerAvx2HookAvailable(text_len: usize) bool {
    return avx2Available() and text_len >= 32;
}

pub fn pretokenizerAsciiBoundaryLanes(text_len: usize) usize {
    if (pretokenizerAvx2HookAvailable(text_len)) {
        return 32;
    }
    if (sse42Available() and text_len >= 16) {
        return 16;
    }
    return 0;
}

// AVX2 hook used by decoder byte-path validation/pack.
pub fn decoderAvx2HookAvailable(token_len: usize) bool {
    return avx2Available() and token_len >= 8;
}

fn selectCountKernelForLen(byte_len: usize) CountKernel {
    if (byte_len >= 64 and avx512Available()) {
        return .avx512;
    }
    if (byte_len >= 32 and avx2Available()) {
        return .avx2;
    }
    if (byte_len >= 16 and sse42Available()) {
        return .sse42;
    }
    return .scalar;
}

fn selectDecodeKernelForLen(token_len: usize) CountKernel {
    if (token_len >= 16 and avx512Available()) {
        return .avx512;
    }
    if (token_len >= 8 and avx2Available()) {
        return .avx2;
    }
    if (token_len >= 4 and sse42Available()) {
        return .sse42;
    }
    return .scalar;
}

fn countNonAsciiScalar(bytes: []const u8) usize {
    var count: usize = 0;
    for (bytes) |byte| {
        count += @intFromBool((byte & 0x80) != 0);
    }
    return count;
}

fn countNonAsciiVec(comptime lanes: usize, bytes: []const u8) usize {
    if (bytes.len == 0) {
        return 0;
    }

    const Vec = @Vector(lanes, u8);

    var count: usize = 0;
    var idx: usize = 0;
    while (idx + lanes <= bytes.len) : (idx += lanes) {
        const chunk_ptr: *const [lanes]u8 = @ptrCast(bytes[idx .. idx + lanes].ptr);
        const chunk: Vec = chunk_ptr.*;
        const high_bits: Vec = chunk >> @as(Vec, @splat(@as(u8, 7)));
        const widened: @Vector(lanes, u16) = @intCast(high_bits);
        count += @as(usize, @intCast(@reduce(.Add, widened)));
    }

    while (idx < bytes.len) : (idx += 1) {
        count += @intFromBool((bytes[idx] & 0x80) != 0);
    }
    return count;
}

pub fn countNonAscii(bytes: []const u8) usize {
    return switch (selectCountKernelForLen(bytes.len)) {
        .avx512 => countNonAsciiVec(64, bytes),
        .avx2 => countNonAsciiVec(32, bytes),
        .sse42 => countNonAsciiVec(16, bytes),
        .scalar => countNonAsciiScalar(bytes),
    };
}

fn encodeU8ToU32Vec(comptime lanes: usize, bytes: []const u8, out: []u32) void {
    std.debug.assert(bytes.len == out.len);
    if (bytes.len == 0) {
        return;
    }

    var idx: usize = 0;
    while (idx + lanes <= bytes.len) : (idx += lanes) {
        const chunk_ptr: *const [lanes]u8 = @ptrCast(bytes[idx .. idx + lanes].ptr);
        const chunk: @Vector(lanes, u8) = chunk_ptr.*;
        const arr: [lanes]u8 = @bitCast(chunk);
        inline for (arr, 0..) |byte, lane| {
            out[idx + lane] = byte;
        }
    }
    while (idx < bytes.len) : (idx += 1) {
        out[idx] = bytes[idx];
    }
}

pub fn encodeU8ToU32(bytes: []const u8, out: []u32) void {
    std.debug.assert(bytes.len == out.len);
    if (bytes.len == 0) {
        return;
    }
    switch (selectCountKernelForLen(bytes.len)) {
        .avx512 => encodeU8ToU32Vec(64, bytes, out),
        .avx2 => encodeU8ToU32Vec(32, bytes, out),
        .sse42 => encodeU8ToU32Vec(16, bytes, out),
        .scalar => {
            for (bytes, 0..) |byte, idx| {
                out[idx] = byte;
            }
        },
    }
}

fn validateAndDecodeU32ToU8Scalar(tokens: []const u32, out: []u8) bool {
    std.debug.assert(tokens.len == out.len);
    for (tokens, 0..) |token, idx| {
        if (token > std.math.maxInt(u8)) {
            return false;
        }
        out[idx] = @as(u8, @intCast(token));
    }
    return true;
}

fn validateAndDecodeU32ToU8Vec(comptime lanes: usize, tokens: []const u32, out: []u8) bool {
    std.debug.assert(tokens.len == out.len);
    if (tokens.len == 0) {
        return true;
    }

    const Vec = @Vector(lanes, u32);
    const max_u8: Vec = @splat(@as(u32, std.math.maxInt(u8)));

    var idx: usize = 0;
    while (idx + lanes <= tokens.len) : (idx += lanes) {
        var lane_buf: [lanes]u32 = undefined;
        @memcpy(std.mem.sliceAsBytes(lane_buf[0..]), std.mem.sliceAsBytes(tokens[idx .. idx + lanes]));
        const chunk: Vec = lane_buf;
        const invalid_mask: @Vector(lanes, bool) = chunk > max_u8;
        if (@reduce(.Or, invalid_mask)) {
            return false;
        }
        const values: [lanes]u32 = @bitCast(chunk);
        inline for (values, 0..) |token, lane| {
            out[idx + lane] = @as(u8, @intCast(token));
        }
    }

    while (idx < tokens.len) : (idx += 1) {
        const token = tokens[idx];
        if (token > std.math.maxInt(u8)) {
            return false;
        }
        out[idx] = @as(u8, @intCast(token));
    }
    return true;
}

pub fn validateAndDecodeU32ToU8Avx2(tokens: []const u32, out: []u8) bool {
    std.debug.assert(tokens.len == out.len);
    if (!decoderAvx2HookAvailable(tokens.len)) {
        return validateAndDecodeU32ToU8(tokens, out);
    }
    return validateAndDecodeU32ToU8Vec(8, tokens, out);
}

pub fn validateAndDecodeU32ToU8(tokens: []const u32, out: []u8) bool {
    return switch (selectDecodeKernelForLen(tokens.len)) {
        .avx512 => validateAndDecodeU32ToU8Vec(16, tokens, out),
        .avx2 => validateAndDecodeU32ToU8Vec(8, tokens, out),
        .sse42 => validateAndDecodeU32ToU8Vec(4, tokens, out),
        .scalar => validateAndDecodeU32ToU8Scalar(tokens, out),
    };
}

test "x86_64 count kernel selection honors AVX512->AVX2->SSE4.2->scalar order" {
    if (builtin.cpu.arch != .x86_64) {
        return;
    }

    const selected = selectedCountKernel();
    if (avx512Available()) {
        try std.testing.expectEqual(CountKernel.avx512, selected);
    } else if (avx2Available()) {
        try std.testing.expectEqual(CountKernel.avx2, selected);
    } else if (sse42Available()) {
        try std.testing.expectEqual(CountKernel.sse42, selected);
    } else {
        try std.testing.expectEqual(CountKernel.scalar, selected);
    }
}

test "x86_64 AVX2 pretokenizer and decoder hooks reflect feature gating" {
    if (builtin.cpu.arch != .x86_64) {
        try std.testing.expect(!pretokenizerAvx2HookAvailable(64));
        try std.testing.expect(!decoderAvx2HookAvailable(64));
        return;
    }

    if (avx2Available()) {
        try std.testing.expect(pretokenizerAvx2HookAvailable(64));
        try std.testing.expect(!pretokenizerAvx2HookAvailable(16));
        try std.testing.expect(decoderAvx2HookAvailable(64));
        try std.testing.expect(!decoderAvx2HookAvailable(4));
    } else {
        try std.testing.expect(!pretokenizerAvx2HookAvailable(64));
        try std.testing.expect(!decoderAvx2HookAvailable(64));
    }
}
