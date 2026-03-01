const builtin = @import("builtin");
const std = @import("std");

pub fn available() bool {
    return builtin.cpu.arch == .wasm32;
}

pub fn simdAvailable() bool {
    return available() and std.Target.wasm.featureSetHas(builtin.cpu.features, .simd128);
}

pub fn countNonAscii(bytes: []const u8) usize {
    if (!simdAvailable() or bytes.len == 0) {
        var fallback: usize = 0;
        for (bytes) |byte| {
            fallback += @intFromBool((byte & 0x80) != 0);
        }
        return fallback;
    }

    const lanes = 16;
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

pub fn encodeU8ToU32(bytes: []const u8, out: []u32) void {
    std.debug.assert(bytes.len == out.len);
    if (!simdAvailable() or bytes.len == 0) {
        for (bytes, 0..) |byte, idx| {
            out[idx] = byte;
        }
        return;
    }

    const lanes = 16;
    var idx: usize = 0;
    while (idx + lanes <= bytes.len) : (idx += lanes) {
        var lane_buf: [lanes]u8 = undefined;
        @memcpy(lane_buf[0..], bytes[idx .. idx + lanes]);
        const chunk: @Vector(lanes, u8) = lane_buf;
        const values: [lanes]u8 = @bitCast(chunk);
        inline for (values, 0..) |byte, lane| {
            out[idx + lane] = byte;
        }
    }
    while (idx < bytes.len) : (idx += 1) {
        out[idx] = bytes[idx];
    }
}

pub fn validateAndDecodeU32ToU8(tokens: []const u32, out: []u8) bool {
    std.debug.assert(tokens.len == out.len);
    if (!simdAvailable() or tokens.len == 0) {
        for (tokens, 0..) |token, idx| {
            if (token > std.math.maxInt(u8)) {
                return false;
            }
            out[idx] = @as(u8, @intCast(token));
        }
        return true;
    }

    const lanes = 4;
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
