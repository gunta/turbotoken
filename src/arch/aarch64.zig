const builtin = @import("builtin");
const std = @import("std");

extern fn turbotoken_arm64_count_non_ascii(bytes: [*]const u8, len: usize) usize;
extern fn turbotoken_arm64_count_non_ascii_dotprod(bytes: [*]const u8, len: usize) usize;
extern fn turbotoken_arm64_decode_u32_to_u8(tokens: [*]const u32, len: usize, out: [*]u8) void;
extern fn turbotoken_arm64_validate_and_decode_u32_to_u8(tokens: [*]const u32, len: usize, out: [*]u8) u32;
extern fn turbotoken_arm64_encode_u8_to_u32(bytes: [*]const u8, len: usize, out: [*]u32) void;

pub const FeatureBit = struct {
    pub const advsimd: u64 = 1 << 0;
    pub const fp16: u64 = 1 << 1;
    pub const dotprod: u64 = 1 << 2;
    pub const bf16: u64 = 1 << 3;
    pub const i8mm: u64 = 1 << 4;
    pub const aes: u64 = 1 << 5;
    pub const pmull: u64 = 1 << 6;
    pub const sha3: u64 = 1 << 7;
    pub const lse: u64 = 1 << 8;
    pub const lse2: u64 = 1 << 9;
    pub const sme: u64 = 1 << 10;
    pub const sme2: u64 = 1 << 11;
};

pub const CountKernel = enum(u32) {
    neon = 1,
    dotprod = 2,
};

var selected_count_kernel: CountKernel = .neon;
var count_kernel_once = std.once(initCountKernel);

fn hasFeature(feature: std.Target.aarch64.Feature) bool {
    return builtin.cpu.arch == .aarch64 and
        std.Target.aarch64.featureSetHas(builtin.cpu.features, feature);
}

pub fn available() bool {
    return hasFeature(.neon);
}

pub fn dotprodAvailable() bool {
    return hasFeature(.dotprod);
}

pub fn featureMask() u64 {
    if (builtin.cpu.arch != .aarch64) {
        return 0;
    }

    var mask: u64 = 0;
    if (hasFeature(.neon)) {
        mask |= FeatureBit.advsimd;
    }
    if (hasFeature(.fullfp16) or hasFeature(.fp16fml)) {
        mask |= FeatureBit.fp16;
    }
    if (hasFeature(.dotprod)) {
        mask |= FeatureBit.dotprod;
    }
    if (hasFeature(.bf16)) {
        mask |= FeatureBit.bf16;
    }
    if (hasFeature(.i8mm)) {
        mask |= FeatureBit.i8mm;
    }
    if (hasFeature(.aes) or hasFeature(.crypto)) {
        mask |= FeatureBit.aes;
        // PMULL is part of the Arm crypto extension on AArch64.
        mask |= FeatureBit.pmull;
    }
    if (hasFeature(.sha3)) {
        mask |= FeatureBit.sha3;
    }
    if (hasFeature(.lse)) {
        mask |= FeatureBit.lse;
    }
    if (hasFeature(.lse2)) {
        mask |= FeatureBit.lse2;
    }
    if (hasFeature(.sme)) {
        mask |= FeatureBit.sme;
    }
    if (hasFeature(.sme2)) {
        mask |= FeatureBit.sme2;
    }
    return mask;
}

fn initCountKernel() void {
    selected_count_kernel = selectCountKernel();
}

fn selectCountKernel() CountKernel {
    if (!dotprodAvailable()) {
        return .neon;
    }

    var sample: [4096]u8 = undefined;
    for (&sample, 0..) |*byte, idx| {
        byte.* = @as(u8, @intCast((idx * 131 + 17) & 0xff));
    }

    const iterations = 512;
    var best_neon: u64 = std.math.maxInt(u64);
    var best_dotprod: u64 = std.math.maxInt(u64);

    for (0..3) |_| {
        best_neon = @min(best_neon, benchmarkCountKernel(.neon, &sample, iterations));
        best_dotprod = @min(best_dotprod, benchmarkCountKernel(.dotprod, &sample, iterations));
    }

    if (best_dotprod * 100 <= best_neon * 99) {
        return .dotprod;
    }
    return .neon;
}

fn benchmarkCountKernel(kernel: CountKernel, sample: []const u8, iterations: usize) u64 {
    var sink: usize = 0;
    var timer = std.time.Timer.start() catch return std.math.maxInt(u64);

    var idx: usize = 0;
    while (idx < iterations) : (idx += 1) {
        const count = switch (kernel) {
            .neon => countNonAsciiNeon(sample),
            .dotprod => countNonAsciiDotProd(sample),
        };
        sink +%= count;
    }

    std.mem.doNotOptimizeAway(sink);
    return timer.read();
}

pub fn countNonAsciiNeon(bytes: []const u8) usize {
    if (bytes.len == 0) {
        return 0;
    }
    return turbotoken_arm64_count_non_ascii(bytes.ptr, bytes.len);
}

pub fn countNonAsciiDotProd(bytes: []const u8) usize {
    if (bytes.len == 0) {
        return 0;
    }
    if (!dotprodAvailable()) {
        return countNonAsciiNeon(bytes);
    }
    return turbotoken_arm64_count_non_ascii_dotprod(bytes.ptr, bytes.len);
}

pub fn selectedCountNonAsciiKernel() CountKernel {
    if (!dotprodAvailable()) {
        return .neon;
    }
    count_kernel_once.call();
    return selected_count_kernel;
}

pub fn countNonAscii(bytes: []const u8) usize {
    if (bytes.len == 0) {
        return 0;
    }
    return switch (selectedCountNonAsciiKernel()) {
        .neon => countNonAsciiNeon(bytes),
        .dotprod => countNonAsciiDotProd(bytes),
    };
}

pub fn decodeU32ToU8(tokens: []const u32, out: []u8) void {
    std.debug.assert(tokens.len == out.len);
    if (tokens.len == 0) {
        return;
    }
    turbotoken_arm64_decode_u32_to_u8(tokens.ptr, tokens.len, out.ptr);
}

pub fn validateAndDecodeU32ToU8(tokens: []const u32, out: []u8) bool {
    std.debug.assert(tokens.len == out.len);
    if (tokens.len == 0) {
        return true;
    }
    return turbotoken_arm64_validate_and_decode_u32_to_u8(tokens.ptr, tokens.len, out.ptr) != 0;
}

pub fn encodeU8ToU32(bytes: []const u8, out: []u32) void {
    std.debug.assert(bytes.len == out.len);
    if (bytes.len == 0) {
        return;
    }
    turbotoken_arm64_encode_u8_to_u32(bytes.ptr, bytes.len, out.ptr);
}

pub fn estimateTokenBound(text: []const u8) usize {
    if (text.len == 0) {
        return 0;
    }

    const non_ascii = countNonAscii(text);
    const ascii = text.len - non_ascii;
    return ((ascii + 3) / 4) + non_ascii;
}

test "aarch64 estimate token bound handles ascii and utf8 bytes" {
    try std.testing.expectEqual(@as(usize, 0), estimateTokenBound(""));
    try std.testing.expectEqual(@as(usize, 2), estimateTokenBound("hello"));

    // "🚀" is four non-ASCII bytes in UTF-8, so this heuristic returns 4.
    try std.testing.expectEqual(@as(usize, 4), estimateTokenBound("🚀"));
    try std.testing.expectEqual(@as(usize, 5), estimateTokenBound("a🚀b"));
}

test "aarch64 decoder packs u32 bytes" {
    var out: [4]u8 = undefined;
    decodeU32ToU8(&[_]u32{ 65, 66, 67, 68 }, &out);
    try std.testing.expectEqualSlices(u8, "ABCD", &out);
}

test "aarch64 validate-and-decode rejects invalid tokens" {
    var out: [4]u8 = undefined;
    try std.testing.expect(validateAndDecodeU32ToU8(&[_]u32{ 65, 66, 67, 68 }, &out));
    try std.testing.expectEqualSlices(u8, "ABCD", &out);
    try std.testing.expect(!validateAndDecodeU32ToU8(&[_]u32{ 65, 66, 300, 68 }, &out));
}

test "aarch64 encoder widens bytes to u32 tokens" {
    var out: [4]u32 = undefined;
    encodeU8ToU32("ABCD", &out);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 65, 66, 67, 68 }, &out);
}

test "aarch64 feature mask includes advsimd on aarch64 targets" {
    if (!available()) {
        return;
    }
    try std.testing.expect((featureMask() & FeatureBit.advsimd) != 0);
}

test "aarch64 non-ascii kernels agree on result" {
    if (!available()) {
        return;
    }

    const sample = "hello-🚀-γειά-世界";

    var scalar_count: usize = 0;
    for (sample) |byte| {
        scalar_count += @intFromBool((byte & 0x80) != 0);
    }

    try std.testing.expectEqual(scalar_count, countNonAsciiNeon(sample));
    try std.testing.expectEqual(scalar_count, countNonAscii(sample));

    if (dotprodAvailable()) {
        try std.testing.expectEqual(scalar_count, countNonAsciiDotProd(sample));
        const selected = selectedCountNonAsciiKernel();
        try std.testing.expect(selected == .neon or selected == .dotprod);
    }
}
