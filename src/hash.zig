const std = @import("std");

// rapidhash v3 constants/flow derived from:
// https://github.com/Nicoshev/rapidhash (MIT License).
const rapid_secret = [8]u64{
    0x2d358dccaa6c78a5,
    0x8bb84b93962eacc9,
    0x4b33a62ed433d4a3,
    0x4d5a2da51de1aa47,
    0xa0761d6478bd642f,
    0xe7037ed1a0b428db,
    0x90ed1765281c388c,
    0xaaaaaaaaaaaaaaaa,
};

fn rapidMum(a: *u64, b: *u64) void {
    const product = @as(u128, a.*) * @as(u128, b.*);
    a.* = @as(u64, @truncate(product));
    b.* = @as(u64, @truncate(product >> 64));
}

fn rapidMix(a: u64, b: u64) u64 {
    var left = a;
    var right = b;
    rapidMum(&left, &right);
    return left ^ right;
}

fn rapidRead64(input: []const u8, start: usize) u64 {
    return std.mem.readInt(u64, input[start..][0..8], .little);
}

fn rapidRead32(input: []const u8, start: usize) u64 {
    return @as(u64, std.mem.readInt(u32, input[start..][0..4], .little));
}

pub fn withSeed(input: []const u8, seed: u64) u64 {
    var mixed_seed = seed ^ rapidMix(seed ^ rapid_secret[2], rapid_secret[1]);
    var a: u64 = 0;
    var b: u64 = 0;
    var i = input.len;
    var p: usize = 0;

    if (input.len <= 16) {
        if (input.len >= 4) {
            mixed_seed ^= @as(u64, input.len);
            if (input.len >= 8) {
                a = rapidRead64(input, p);
                b = rapidRead64(input, input.len - 8);
            } else {
                a = rapidRead32(input, p);
                b = rapidRead32(input, input.len - 4);
            }
        } else if (input.len > 0) {
            a = (@as(u64, input[0]) << 45) | @as(u64, input[input.len - 1]);
            b = @as(u64, input[input.len >> 1]);
        }
    } else {
        if (i > 112) {
            var see1 = mixed_seed;
            var see2 = mixed_seed;
            var see3 = mixed_seed;
            var see4 = mixed_seed;
            var see5 = mixed_seed;
            var see6 = mixed_seed;

            while (i > 112) {
                mixed_seed = rapidMix(rapidRead64(input, p) ^ rapid_secret[0], rapidRead64(input, p + 8) ^ mixed_seed);
                see1 = rapidMix(rapidRead64(input, p + 16) ^ rapid_secret[1], rapidRead64(input, p + 24) ^ see1);
                see2 = rapidMix(rapidRead64(input, p + 32) ^ rapid_secret[2], rapidRead64(input, p + 40) ^ see2);
                see3 = rapidMix(rapidRead64(input, p + 48) ^ rapid_secret[3], rapidRead64(input, p + 56) ^ see3);
                see4 = rapidMix(rapidRead64(input, p + 64) ^ rapid_secret[4], rapidRead64(input, p + 72) ^ see4);
                see5 = rapidMix(rapidRead64(input, p + 80) ^ rapid_secret[5], rapidRead64(input, p + 88) ^ see5);
                see6 = rapidMix(rapidRead64(input, p + 96) ^ rapid_secret[6], rapidRead64(input, p + 104) ^ see6);
                p += 112;
                i -= 112;
            }

            mixed_seed ^= see1;
            see2 ^= see3;
            see4 ^= see5;
            mixed_seed ^= see6;
            see2 ^= see4;
            mixed_seed ^= see2;
        }

        if (i > 16) {
            mixed_seed = rapidMix(rapidRead64(input, p) ^ rapid_secret[2], rapidRead64(input, p + 8) ^ mixed_seed);
            if (i > 32) {
                mixed_seed = rapidMix(rapidRead64(input, p + 16) ^ rapid_secret[2], rapidRead64(input, p + 24) ^ mixed_seed);
                if (i > 48) {
                    mixed_seed = rapidMix(rapidRead64(input, p + 32) ^ rapid_secret[1], rapidRead64(input, p + 40) ^ mixed_seed);
                    if (i > 64) {
                        mixed_seed = rapidMix(rapidRead64(input, p + 48) ^ rapid_secret[1], rapidRead64(input, p + 56) ^ mixed_seed);
                        if (i > 80) {
                            mixed_seed = rapidMix(rapidRead64(input, p + 64) ^ rapid_secret[2], rapidRead64(input, p + 72) ^ mixed_seed);
                            if (i > 96) {
                                mixed_seed = rapidMix(rapidRead64(input, p + 80) ^ rapid_secret[1], rapidRead64(input, p + 88) ^ mixed_seed);
                            }
                        }
                    }
                }
            }
        }

        a = rapidRead64(input, p + i - 16) ^ @as(u64, i);
        b = rapidRead64(input, p + i - 8);
    }

    a ^= rapid_secret[1];
    b ^= mixed_seed;
    rapidMum(&a, &b);
    return rapidMix(a ^ rapid_secret[7], b ^ rapid_secret[1] ^ @as(u64, i));
}

pub fn bytes(input: []const u8) u64 {
    return withSeed(input, 0);
}

test "rapidhash output is deterministic for representative inputs" {
    try std.testing.expectEqual(@as(u64, 232177599295442350), bytes(""));
    try std.testing.expectEqual(@as(u64, 13499579190546594898), bytes("turbotoken"));
    try std.testing.expectEqual(@as(u64, 9178694193904926662), bytes("abcdefghijklmnopqrstuvwxyz012345"));
    try std.testing.expectEqual(@as(u64, 13499579190546594898), withSeed("turbotoken", 0));
    try std.testing.expectEqual(@as(u64, 8228851765041995692), withSeed("turbotoken", 1));
}
