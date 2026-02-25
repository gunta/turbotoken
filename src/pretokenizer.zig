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
