const std = @import("std");
const builtin = @import("builtin");
const wasm_arch = @import("arch/wasm.zig");

fn runtimeAllocator() std.mem.Allocator {
    if (builtin.os.tag == .freestanding and builtin.cpu.arch == .wasm32) {
        return std.heap.wasm_allocator;
    }
    if (builtin.os.tag == .freestanding) {
        return std.heap.page_allocator;
    }
    return std.heap.c_allocator;
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

    if (text_len > 0 and text == null) {
        return -1;
    }
    if (out_cap < text_len) {
        return -1;
    }

    const in_slice: []const u8 = if (text_len == 0) &[_]u8{} else text[0..text_len];
    const out_slice = out_tokens[0..text_len];

    if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable() and text_len >= 16) {
        wasm_arch.encodeU8ToU32(in_slice, out_slice);
        return @as(isize, @intCast(text_len));
    }

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

    if (token_len > 0 and tokens == null) {
        return -1;
    }
    if (out_cap < token_len) {
        return -1;
    }

    const in_slice: []const u32 = if (token_len == 0) &[_]u32{} else tokens[0..token_len];
    const out_slice = out_bytes[0..token_len];

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

comptime {
    _ = turbotoken_version;
    _ = turbotoken_wasm_alloc;
    _ = turbotoken_wasm_free;
    _ = turbotoken_encode_utf8_bytes;
    _ = turbotoken_decode_utf8_bytes;
}

test "npm wasm utf8 roundtrip" {
    const input = "hello";
    var tokens: [5]u32 = undefined;
    const written = turbotoken_encode_utf8_bytes(input.ptr, input.len, &tokens, tokens.len);
    try std.testing.expectEqual(@as(isize, 5), written);

    var out: [5]u8 = undefined;
    const decoded = turbotoken_decode_utf8_bytes(&tokens, @as(usize, @intCast(written)), &out, out.len);
    try std.testing.expectEqual(@as(isize, 5), decoded);
    try std.testing.expectEqualSlices(u8, input, out[0..@as(usize, @intCast(decoded))]);
}
