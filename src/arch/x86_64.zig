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
        var lane_buf: [lanes]u8 = undefined;
        @memcpy(lane_buf[0..], bytes[idx .. idx + lanes]);
        const chunk: Vec = lane_buf;
        const mask: @Vector(lanes, bool) = (chunk & @as(Vec, @splat(@as(u8, 0x80)))) != @as(Vec, @splat(0));
        const lane_counts: Vec = @select(
            u8,
            mask,
            @as(Vec, @splat(@as(u8, 1))),
            @as(Vec, @splat(@as(u8, 0))),
        );
        const counts_arr: [lanes]u8 = @bitCast(lane_counts);
        inline for (counts_arr) |lane_count| {
            count += lane_count;
        }
    }

    while (idx < bytes.len) : (idx += 1) {
        count += @intFromBool((bytes[idx] & 0x80) != 0);
    }
    return count;
}

pub fn countNonAscii(bytes: []const u8) usize {
    return switch (selectedCountKernel()) {
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
        var lane_buf: [lanes]u8 = undefined;
        @memcpy(lane_buf[0..], bytes[idx .. idx + lanes]);
        const chunk: @Vector(lanes, u8) = lane_buf;
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
    switch (selectedCountKernel()) {
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

pub fn validateAndDecodeU32ToU8(tokens: []const u32, out: []u8) bool {
    return switch (selectedCountKernel()) {
        .avx512 => validateAndDecodeU32ToU8Vec(16, tokens, out),
        .avx2 => validateAndDecodeU32ToU8Vec(8, tokens, out),
        .sse42 => validateAndDecodeU32ToU8Vec(4, tokens, out),
        .scalar => validateAndDecodeU32ToU8Scalar(tokens, out),
    };
}
