const std = @import("std");

pub fn formatTokens(writer: anytype, tokens: []const u32, json_mode: bool) !void {
    if (json_mode) {
        try writer.writeByte('[');
        for (tokens, 0..) |token, i| {
            if (i > 0) try writer.writeAll(", ");
            try std.fmt.format(writer, "{d}", .{token});
        }
        try writer.writeByte(']');
        try writer.writeByte('\n');
    } else {
        for (tokens, 0..) |token, i| {
            if (i > 0) try writer.writeByte(' ');
            try std.fmt.format(writer, "{d}", .{token});
        }
        try writer.writeByte('\n');
    }
}

pub fn formatCount(writer: anytype, count_val: usize, json_mode: bool) !void {
    if (json_mode) {
        try std.fmt.format(writer, "{{\"count\": {d}}}\n", .{count_val});
    } else {
        try std.fmt.format(writer, "{d}\n", .{count_val});
    }
}

pub fn formatDecoded(writer: anytype, bytes: []const u8, json_mode: bool) !void {
    if (json_mode) {
        try writer.writeByte('"');
        for (bytes) |byte| {
            switch (byte) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => {
                    if (byte < 0x20) {
                        try std.fmt.format(writer, "\\u{x:0>4}", .{byte});
                    } else {
                        try writer.writeByte(byte);
                    }
                },
            }
        }
        try writer.writeByte('"');
        try writer.writeByte('\n');
    } else {
        try writer.writeAll(bytes);
        try writer.writeByte('\n');
    }
}

pub fn formatVersion(writer: anytype, ver: []const u8, json_mode: bool) !void {
    if (json_mode) {
        try std.fmt.format(writer, "{{\"version\": \"{s}\"}}\n", .{ver});
    } else {
        try std.fmt.format(writer, "turbotoken {s}\n", .{ver});
    }
}
