const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");

pub const SplitError = error{
    UnsupportedInput,
    OutputTooSmall,
    RangeOverflow,
};

pub fn estimateTokenBound(text: []const u8) usize {
    if (text.len == 0) {
        return 0;
    }

    if (builtin.cpu.arch == .aarch64 and aarch64.available()) {
        return aarch64.estimateTokenBound(text);
    }

    return (text.len + 3) / 4;
}

fn isAsciiLetter(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z');
}

fn classifyAsciiByte(byte: u8) u8 {
    if (byte == ' ') {
        return 0;
    }
    if (isAsciiLetter(byte)) {
        return 1;
    }
    if (byte >= '0' and byte <= '9') {
        return 2;
    }
    if (byte >= 33 and byte <= 126) {
        return 3;
    }
    return 4;
}

fn classifyAsciiChunk16(chunk: @Vector(16, u8)) @Vector(16, u8) {
    const Vec16u8 = @Vector(16, u8);
    const Vec16b = @Vector(16, bool);
    const code_space = @as(Vec16u8, @splat(@as(u8, 0)));
    const code_letter = @as(Vec16u8, @splat(@as(u8, 1)));
    const code_digit = @as(Vec16u8, @splat(@as(u8, 2)));
    const code_punct = @as(Vec16u8, @splat(@as(u8, 3)));
    const code_other = @as(Vec16u8, @splat(@as(u8, 4)));

    const is_ascii: Vec16b = chunk < @as(Vec16u8, @splat(@as(u8, 0x80)));
    const is_space: Vec16b = chunk == @as(Vec16u8, @splat(@as(u8, ' ')));
    const is_upper: Vec16b = (chunk >= @as(Vec16u8, @splat(@as(u8, 'A')))) & (chunk <= @as(Vec16u8, @splat(@as(u8, 'Z'))));
    const is_lower: Vec16b = (chunk >= @as(Vec16u8, @splat(@as(u8, 'a')))) & (chunk <= @as(Vec16u8, @splat(@as(u8, 'z'))));
    const is_letter: Vec16b = is_upper | is_lower;
    const is_digit: Vec16b = (chunk >= @as(Vec16u8, @splat(@as(u8, '0')))) & (chunk <= @as(Vec16u8, @splat(@as(u8, '9'))));
    const is_printable: Vec16b = is_ascii & (chunk >= @as(Vec16u8, @splat(@as(u8, 33)))) & (chunk <= @as(Vec16u8, @splat(@as(u8, 126))));
    const is_punct: Vec16b = is_printable & ~(is_space | is_letter | is_digit);

    var out = code_other;
    out = @select(u8, is_punct, code_punct, out);
    out = @select(u8, is_digit, code_digit, out);
    out = @select(u8, is_letter, code_letter, out);
    out = @select(u8, is_space, code_space, out);
    return out;
}

pub fn countAsciiClassBoundariesScalar(text: []const u8) usize {
    if (text.len <= 1) {
        return 0;
    }

    var boundaries: usize = 0;
    var prev = classifyAsciiByte(text[0]);
    for (text[1..]) |byte| {
        const cls = classifyAsciiByte(byte);
        if (cls != prev) {
            boundaries += 1;
        }
        prev = cls;
    }
    return boundaries;
}

fn countAsciiClassBoundariesNeonLike(text: []const u8) usize {
    if (text.len <= 1) {
        return 0;
    }

    var boundaries: usize = 0;
    var prev = classifyAsciiByte(text[0]);
    var idx: usize = 1;

    while (idx + 16 <= text.len) : (idx += 16) {
        const chunk_ptr: *const [16]u8 = @ptrCast(text[idx .. idx + 16].ptr);
        const chunk: @Vector(16, u8) = chunk_ptr.*;
        const classes: @Vector(16, u8) = classifyAsciiChunk16(chunk);
        const classes_arr: [16]u8 = @bitCast(classes);
        inline for (classes_arr) |cls| {
            if (cls != prev) {
                boundaries += 1;
            }
            prev = cls;
        }
    }

    while (idx < text.len) : (idx += 1) {
        const cls = classifyAsciiByte(text[idx]);
        if (cls != prev) {
            boundaries += 1;
        }
        prev = cls;
    }

    return boundaries;
}

pub fn countAsciiClassBoundariesNeon(text: []const u8) usize {
    return countAsciiClassBoundariesNeonLike(text);
}

pub fn countAsciiClassBoundaries(text: []const u8) usize {
    if (text.len <= 1) {
        return 0;
    }
    if (builtin.cpu.arch == .aarch64 and aarch64.available() and text.len >= 32) {
        return countAsciiClassBoundariesNeonLike(text);
    }
    return countAsciiClassBoundariesScalar(text);
}

fn emitRange(
    starts_opt: ?[]u32,
    ends_opt: ?[]u32,
    range_idx: usize,
    start: usize,
    end: usize,
) SplitError!void {
    if ((starts_opt == null) != (ends_opt == null)) {
        return error.OutputTooSmall;
    }
    if (starts_opt == null or ends_opt == null) {
        return;
    }

    const starts = starts_opt.?;
    const ends = ends_opt.?;
    if (range_idx >= starts.len or range_idx >= ends.len) {
        return error.OutputTooSmall;
    }
    if (start > std.math.maxInt(u32) or end > std.math.maxInt(u32)) {
        return error.RangeOverflow;
    }

    starts[range_idx] = @as(u32, @intCast(start));
    ends[range_idx] = @as(u32, @intCast(end));
}

pub fn splitAsciiLetterSpaceRanges(
    text: []const u8,
    out_starts_opt: ?[]u32,
    out_ends_opt: ?[]u32,
) SplitError!usize {
    if ((out_starts_opt == null) != (out_ends_opt == null)) {
        return error.OutputTooSmall;
    }

    var range_count: usize = 0;
    var idx: usize = 0;

    while (idx < text.len) {
        const byte = text[idx];
        if (isAsciiLetter(byte)) {
            var end = idx + 1;
            while (end < text.len and isAsciiLetter(text[end])) : (end += 1) {}
            try emitRange(out_starts_opt, out_ends_opt, range_count, idx, end);
            range_count += 1;
            idx = end;
            continue;
        }

        if (byte == ' ') {
            var run_end = idx + 1;
            while (run_end < text.len and text[run_end] == ' ') : (run_end += 1) {}

            // Match the common tiktoken family regex behavior for ASCII words:
            // extra spaces stay standalone and exactly one leading space attaches to the word.
            if (run_end < text.len and isAsciiLetter(text[run_end])) {
                const extra_spaces = (run_end - idx) - 1;
                if (extra_spaces > 0) {
                    const extra_end = idx + extra_spaces;
                    try emitRange(out_starts_opt, out_ends_opt, range_count, idx, extra_end);
                    range_count += 1;
                }

                var word_end = run_end + 1;
                while (word_end < text.len and isAsciiLetter(text[word_end])) : (word_end += 1) {}
                try emitRange(out_starts_opt, out_ends_opt, range_count, run_end - 1, word_end);
                range_count += 1;
                idx = word_end;
                continue;
            }

            try emitRange(out_starts_opt, out_ends_opt, range_count, idx, run_end);
            range_count += 1;
            idx = run_end;
            continue;
        }

        return error.UnsupportedInput;
    }

    return range_count;
}

test "generic token bound heuristic remains stable on non-aarch64 paths" {
    try std.testing.expectEqual(@as(usize, 0), estimateTokenBound(""));
    try std.testing.expectEqual(@as(usize, 2), estimateTokenBound("hello"));
}

test "split ascii letter/space ranges attaches exactly one leading space to words" {
    const input = "hello  world   again";
    var starts: [8]u32 = undefined;
    var ends: [8]u32 = undefined;

    const written = try splitAsciiLetterSpaceRanges(input, &starts, &ends);
    try std.testing.expectEqual(@as(usize, 5), written);

    const expected = [_][]const u8{
        "hello",
        " ",
        " world",
        "  ",
        " again",
    };
    for (expected, 0..) |piece, idx| {
        const start = @as(usize, starts[idx]);
        const end = @as(usize, ends[idx]);
        try std.testing.expectEqualSlices(u8, piece, input[start..end]);
    }
}

test "split ascii letter/space ranges rejects unsupported bytes" {
    var starts: [4]u32 = undefined;
    var ends: [4]u32 = undefined;
    try std.testing.expectError(
        error.UnsupportedInput,
        splitAsciiLetterSpaceRanges("hello, world", &starts, &ends),
    );
}

test "ascii class boundary counter matches scalar baseline" {
    const text = "hello 123!! world\tz\xff";
    try std.testing.expectEqual(
        countAsciiClassBoundariesScalar(text),
        countAsciiClassBoundaries(text),
    );
}

test "ascii class boundary counter handles empty and single-byte inputs" {
    try std.testing.expectEqual(@as(usize, 0), countAsciiClassBoundaries(""));
    try std.testing.expectEqual(@as(usize, 0), countAsciiClassBoundaries("a"));
}
