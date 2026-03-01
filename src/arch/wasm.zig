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
        const chunk_ptr: *const [lanes]u8 = @ptrCast(bytes[idx .. idx + lanes].ptr);
        const chunk: @Vector(lanes, u8) = chunk_ptr.*;
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
        const chunk_ptr: *const [lanes]u32 = @ptrCast(tokens[idx .. idx + lanes].ptr);
        const chunk: Vec = chunk_ptr.*;
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

test "wasm countNonAscii matches scalar result" {
    const sample = "hello-🚀-γειά-世界";
    var scalar: usize = 0;
    for (sample) |byte| {
        scalar += @intFromBool((byte & 0x80) != 0);
    }
    try std.testing.expectEqual(scalar, countNonAscii(sample));
}

test "wasm encode/decode byte helpers roundtrip" {
    const sample = "0123456789abcdef0123456789abcdef";
    var tokens: [sample.len]u32 = undefined;
    var out: [sample.len]u8 = undefined;
    encodeU8ToU32(sample, &tokens);
    try std.testing.expect(validateAndDecodeU32ToU8(&tokens, &out));
    try std.testing.expectEqualSlices(u8, sample, &out);
}
