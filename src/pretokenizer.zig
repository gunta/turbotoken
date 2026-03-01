const std = @import("std");
const builtin = @import("builtin");
const aarch64 = @import("arch/aarch64.zig");
const x86_64 = @import("arch/x86_64.zig");
const wasm_arch = @import("arch/wasm.zig");

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

fn isAsciiUpper(byte: u8) bool {
    return byte >= 'A' and byte <= 'Z';
}

fn isAsciiLower(byte: u8) bool {
    return byte >= 'a' and byte <= 'z';
}

fn isAsciiDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0B, 0x0C => true,
        else => false,
    };
}

fn isAsciiNewline(byte: u8) bool {
    return byte == '\n' or byte == '\r';
}

fn toAsciiLower(byte: u8) u8 {
    if (byte >= 'A' and byte <= 'Z') {
        return byte + 32;
    }
    return byte;
}

fn isAlt12Prefix(byte: u8) bool {
    return byte != '\r' and byte != '\n' and !isAsciiLetter(byte) and !isAsciiDigit(byte);
}

fn contractionSuffixLen(text: []const u8, start: usize) usize {
    if (start + 1 >= text.len) {
        return 0;
    }
    if (text[start] != '\'') {
        return 0;
    }

    const c1 = toAsciiLower(text[start + 1]);
    if (c1 == 's' or c1 == 't' or c1 == 'm' or c1 == 'd') {
        return 2;
    }
    if (start + 2 >= text.len) {
        return 0;
    }
    const c2 = toAsciiLower(text[start + 2]);
    if (c1 == 'r' and c2 == 'e') {
        return 3;
    }
    if (c1 == 'v' and c2 == 'e') {
        return 3;
    }
    if (c1 == 'l' and c2 == 'l') {
        return 3;
    }
    return 0;
}

fn parseAlt1Core(text: []const u8, start: usize) ?usize {
    var idx = start;
    while (idx < text.len and isAsciiUpper(text[idx])) : (idx += 1) {}
    const lower_start = idx;
    while (idx < text.len and isAsciiLower(text[idx])) : (idx += 1) {}
    if (idx == lower_start) {
        return null;
    }
    idx += contractionSuffixLen(text, idx);
    return idx;
}

fn parseAlt2Core(text: []const u8, start: usize) ?usize {
    var idx = start;
    const upper_start = idx;
    while (idx < text.len and isAsciiUpper(text[idx])) : (idx += 1) {}
    if (idx == upper_start) {
        return null;
    }
    while (idx < text.len and isAsciiLower(text[idx])) : (idx += 1) {}
    idx += contractionSuffixLen(text, idx);
    return idx;
}

fn matchAlt1Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len) {
        return null;
    }
    if (isAlt12Prefix(text[start]) and start + 1 < text.len) {
        if (parseAlt1Core(text, start + 1)) |end| {
            return end;
        }
    }
    return parseAlt1Core(text, start);
}

fn matchAlt2Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len) {
        return null;
    }
    if (isAlt12Prefix(text[start]) and start + 1 < text.len) {
        if (parseAlt2Core(text, start + 1)) |end| {
            return end;
        }
    }
    return parseAlt2Core(text, start);
}

fn isAlt4Core(byte: u8) bool {
    return !isAsciiWhitespace(byte) and !isAsciiLetter(byte) and !isAsciiDigit(byte);
}

fn matchAlt4Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len) {
        return null;
    }
    var idx = start;
    if (text[idx] == ' ' and idx + 1 < text.len and isAlt4Core(text[idx + 1])) {
        idx += 1;
    }
    if (!isAlt4Core(text[idx])) {
        return null;
    }
    idx += 1;
    while (idx < text.len and isAlt4Core(text[idx])) : (idx += 1) {}
    while (idx < text.len and (text[idx] == '\r' or text[idx] == '\n' or text[idx] == '/')) : (idx += 1) {}
    return idx;
}

fn matchAlt5Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len or !isAsciiWhitespace(text[start])) {
        return null;
    }
    var idx = start;
    var last_newline: ?usize = null;
    while (idx < text.len and isAsciiWhitespace(text[idx])) : (idx += 1) {
        if (isAsciiNewline(text[idx])) {
            last_newline = idx;
        }
    }
    if (last_newline) |pos| {
        return pos + 1;
    }
    return null;
}

fn matchAlt6Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len or !isAsciiWhitespace(text[start])) {
        return null;
    }

    var run_end = start;
    while (run_end < text.len and isAsciiWhitespace(text[run_end])) : (run_end += 1) {}
    const run_len = run_end - start;
    if (run_len == 0) {
        return null;
    }

    // \s+(?!\S): greedy \s+ will backtrack until the next char is not non-whitespace.
    // For runs that end at EOF, consume the full run.
    if (run_end == text.len) {
        return run_end;
    }

    // For runs followed by non-whitespace, consume all but the final whitespace byte.
    if (run_len >= 2) {
        return run_end - 1;
    }
    return null;
}

fn matchAlt7Ascii(text: []const u8, start: usize) ?usize {
    if (start >= text.len or !isAsciiWhitespace(text[start])) {
        return null;
    }
    var idx = start;
    while (idx < text.len and isAsciiWhitespace(text[idx])) : (idx += 1) {}
    return idx;
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

fn classifyAsciiChunk(comptime lanes: usize, chunk: @Vector(lanes, u8)) @Vector(lanes, u8) {
    const VecU8 = @Vector(lanes, u8);
    const VecB = @Vector(lanes, bool);
    const code_space = @as(VecU8, @splat(@as(u8, 0)));
    const code_letter = @as(VecU8, @splat(@as(u8, 1)));
    const code_digit = @as(VecU8, @splat(@as(u8, 2)));
    const code_punct = @as(VecU8, @splat(@as(u8, 3)));
    const code_other = @as(VecU8, @splat(@as(u8, 4)));

    const is_ascii: VecB = chunk < @as(VecU8, @splat(@as(u8, 0x80)));
    const is_space: VecB = chunk == @as(VecU8, @splat(@as(u8, ' ')));
    const is_upper: VecB = (chunk >= @as(VecU8, @splat(@as(u8, 'A')))) & (chunk <= @as(VecU8, @splat(@as(u8, 'Z'))));
    const is_lower: VecB = (chunk >= @as(VecU8, @splat(@as(u8, 'a')))) & (chunk <= @as(VecU8, @splat(@as(u8, 'z'))));
    const is_letter: VecB = is_upper | is_lower;
    const is_digit: VecB = (chunk >= @as(VecU8, @splat(@as(u8, '0')))) & (chunk <= @as(VecU8, @splat(@as(u8, '9'))));
    const is_printable: VecB = is_ascii & (chunk >= @as(VecU8, @splat(@as(u8, 33)))) & (chunk <= @as(VecU8, @splat(@as(u8, 126))));
    const is_punct: VecB = is_printable & ~(is_space | is_letter | is_digit);

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

fn countAsciiClassBoundariesVec(comptime lanes: usize, text: []const u8) usize {
    if (text.len <= 1) {
        return 0;
    }

    var boundaries: usize = 0;
    var prev = classifyAsciiByte(text[0]);
    var idx: usize = 1;

    while (idx + lanes <= text.len) : (idx += lanes) {
        const chunk_ptr: *const [lanes]u8 = @ptrCast(text[idx .. idx + lanes].ptr);
        const chunk: @Vector(lanes, u8) = chunk_ptr.*;
        const classes: @Vector(lanes, u8) = classifyAsciiChunk(lanes, chunk);
        const classes_arr: [lanes]u8 = @bitCast(classes);
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
    return countAsciiClassBoundariesVec(16, text);
}

pub fn countAsciiClassBoundaries(text: []const u8) usize {
    if (text.len <= 1) {
        return 0;
    }
    if (builtin.cpu.arch == .aarch64 and aarch64.available() and text.len >= 32) {
        return countAsciiClassBoundariesVec(16, text);
    }
    if (builtin.cpu.arch == .x86_64) {
        if (x86_64.pretokenizerAvx2HookAvailable(text.len)) {
            return countAsciiClassBoundariesVec(32, text);
        }
        const x86_lanes = x86_64.pretokenizerAsciiBoundaryLanes(text.len);
        if (x86_lanes == 16) {
            return countAsciiClassBoundariesVec(16, text);
        }
    }
    if (builtin.cpu.arch == .wasm32 and wasm_arch.simdAvailable() and text.len >= 32) {
        return countAsciiClassBoundariesVec(16, text);
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
    while (try nextAsciiLetterSpaceRange(text, &idx)) |range| {
        try emitRange(out_starts_opt, out_ends_opt, range_count, range.start, range.end);
        range_count += 1;
    }

    return range_count;
}

pub fn nextAsciiLetterSpaceRange(text: []const u8, idx: *usize) SplitError!?AsciiRange {
    if (idx.* >= text.len) {
        return null;
    }

    const start = idx.*;
    const byte = text[start];
    if (isAsciiLetter(byte)) {
        var end = start + 1;
        while (end < text.len and isAsciiLetter(text[end])) : (end += 1) {}
        idx.* = end;
        return AsciiRange{ .start = start, .end = end };
    }

    if (byte == ' ') {
        var run_end = start + 1;
        while (run_end < text.len and text[run_end] == ' ') : (run_end += 1) {}

        // Match the common tiktoken family regex behavior for ASCII words:
        // extra spaces stay standalone and exactly one leading space attaches to the word.
        if (run_end < text.len and isAsciiLetter(text[run_end])) {
            const extra_spaces = (run_end - start) - 1;
            if (extra_spaces > 0) {
                const extra_end = start + extra_spaces;
                idx.* = extra_end;
                return AsciiRange{ .start = start, .end = extra_end };
            }

            var word_end = run_end + 1;
            while (word_end < text.len and isAsciiLetter(text[word_end])) : (word_end += 1) {}
            idx.* = word_end;
            return AsciiRange{ .start = run_end - 1, .end = word_end };
        }

        idx.* = run_end;
        return AsciiRange{ .start = start, .end = run_end };
    }

    return error.UnsupportedInput;
}

pub fn splitAsciiO200kRanges(
    text: []const u8,
    out_starts_opt: ?[]u32,
    out_ends_opt: ?[]u32,
) SplitError!usize {
    if ((out_starts_opt == null) != (out_ends_opt == null)) {
        return error.OutputTooSmall;
    }

    var range_count: usize = 0;
    var idx: usize = 0;
    while (try nextAsciiO200kRange(text, &idx)) |range| {
        try emitRange(out_starts_opt, out_ends_opt, range_count, range.start, range.end);
        range_count += 1;
    }
    return range_count;
}

pub const AsciiRange = struct {
    start: usize,
    end: usize,
};

pub fn nextAsciiO200kRange(text: []const u8, idx: *usize) SplitError!?AsciiRange {
    if (idx.* >= text.len) {
        return null;
    }

    const start = idx.*;
    const byte = text[start];
    if (byte >= 0x80) {
        return error.UnsupportedInput;
    }

    if (isAlt12Prefix(byte) and start + 1 < text.len and isAsciiLetter(text[start + 1])) {
        if (parseAlt1Core(text, start + 1)) |core_end| {
            idx.* = core_end;
            return AsciiRange{ .start = start, .end = core_end };
        }
        if (parseAlt2Core(text, start + 1)) |core_end| {
            idx.* = core_end;
            return AsciiRange{ .start = start, .end = core_end };
        }
    }

    if (isAsciiWhitespace(byte)) {
        if (matchAlt5Ascii(text, start)) |end| {
            if (end > start) {
                idx.* = end;
                return AsciiRange{ .start = start, .end = end };
            }
        }
        if (matchAlt6Ascii(text, start)) |end| {
            if (end > start) {
                idx.* = end;
                return AsciiRange{ .start = start, .end = end };
            }
        }
        if (matchAlt7Ascii(text, start)) |end| {
            if (end > start) {
                idx.* = end;
                return AsciiRange{ .start = start, .end = end };
            }
        }
        return error.UnsupportedInput;
    }

    if (isAsciiDigit(byte)) {
        var end = start + 1;
        var digits: usize = 1;
        while (end < text.len and digits < 3 and isAsciiDigit(text[end])) : ({
            end += 1;
            digits += 1;
        }) {}
        idx.* = end;
        return AsciiRange{ .start = start, .end = end };
    }

    if (isAsciiLetter(byte)) {
        if (parseAlt1Core(text, start)) |end| {
            idx.* = end;
            return AsciiRange{ .start = start, .end = end };
        }
        if (parseAlt2Core(text, start)) |end| {
            idx.* = end;
            return AsciiRange{ .start = start, .end = end };
        }
        return error.UnsupportedInput;
    }

    if (matchAlt4Ascii(text, start)) |end| {
        if (end > start) {
            idx.* = end;
            return AsciiRange{ .start = start, .end = end };
        }
    }

    return error.UnsupportedInput;
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

test "next ascii letter/space range iterator matches split helper output" {
    const input = "hello  world   again";
    var starts: [8]u32 = undefined;
    var ends: [8]u32 = undefined;
    const written = try splitAsciiLetterSpaceRanges(input, &starts, &ends);

    var idx: usize = 0;
    var out_idx: usize = 0;
    while (try nextAsciiLetterSpaceRange(input, &idx)) |range| {
        try std.testing.expect(out_idx < written);
        try std.testing.expectEqual(@as(usize, starts[out_idx]), range.start);
        try std.testing.expectEqual(@as(usize, ends[out_idx]), range.end);
        out_idx += 1;
    }
    try std.testing.expectEqual(written, out_idx);
}

test "split ascii o200k ranges handles words punctuation and newlines" {
    const input = "Tokenizer matters, for coding agents.\n";
    var starts: [32]u32 = undefined;
    var ends: [32]u32 = undefined;

    const written = try splitAsciiO200kRanges(input, &starts, &ends);
    const expected = [_][]const u8{
        "Tokenizer",
        " matters",
        ",",
        " for",
        " coding",
        " agents",
        ".\n",
    };
    try std.testing.expectEqual(expected.len, written);
    for (expected, 0..) |piece, idx| {
        const start = @as(usize, starts[idx]);
        const end = @as(usize, ends[idx]);
        try std.testing.expectEqualSlices(u8, piece, input[start..end]);
    }
}

test "split ascii o200k ranges supports apostrophe contractions" {
    const input = "we're I'M he'll she'd";
    var starts: [16]u32 = undefined;
    var ends: [16]u32 = undefined;

    const written = try splitAsciiO200kRanges(input, &starts, &ends);
    const expected = [_][]const u8{
        "we're",
        " I'M",
        " he'll",
        " she'd",
    };
    try std.testing.expectEqual(expected.len, written);
    for (expected, 0..) |piece, idx| {
        const start = @as(usize, starts[idx]);
        const end = @as(usize, ends[idx]);
        try std.testing.expectEqualSlices(u8, piece, input[start..end]);
    }
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
