const std = @import("std");

pub const Command = enum {
    encode,
    decode,
    count,
    chat,
    version,
    list_encodings,
    list_models,
    help,
};

pub const ParsedArgs = struct {
    command: Command,
    encoding_name: []const u8 = "o200k_base",
    model_name: ?[]const u8 = null,
    json_output: bool = false,
    file_path: ?[]const u8 = null,
    rank_file_path: ?[]const u8 = null,
    no_download: bool = false,
    positional: ?[]const u8 = null,
};

pub const ParseError = error{
    UnknownCommand,
    UnknownFlag,
    MissingValue,
};

pub fn parseArgs(allocator: std.mem.Allocator, args_iter: anytype) !ParsedArgs {
    _ = allocator;
    var result = ParsedArgs{
        .command = .help,
    };

    // First non-flag arg is the command
    var got_command = false;
    while (args_iter.next()) |arg| {
        if (!got_command) {
            if (std.mem.eql(u8, arg, "encode")) {
                result.command = .encode;
            } else if (std.mem.eql(u8, arg, "decode")) {
                result.command = .decode;
            } else if (std.mem.eql(u8, arg, "count")) {
                result.command = .count;
            } else if (std.mem.eql(u8, arg, "chat")) {
                result.command = .chat;
            } else if (std.mem.eql(u8, arg, "version")) {
                result.command = .version;
            } else if (std.mem.eql(u8, arg, "list-encodings")) {
                result.command = .list_encodings;
            } else if (std.mem.eql(u8, arg, "list-models")) {
                result.command = .list_models;
            } else if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                result.command = .help;
            } else {
                return ParseError.UnknownCommand;
            }
            got_command = true;
            continue;
        }

        // Parse flags
        if (std.mem.eql(u8, arg, "-e") or std.mem.eql(u8, arg, "--encoding")) {
            result.encoding_name = args_iter.next() orelse return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            result.model_name = args_iter.next() orelse return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--json")) {
            result.json_output = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--file")) {
            result.file_path = args_iter.next() orelse return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--rank-file")) {
            result.rank_file_path = args_iter.next() orelse return ParseError.MissingValue;
        } else if (std.mem.eql(u8, arg, "--no-download")) {
            result.no_download = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return ParseError.UnknownFlag;
        } else {
            // Positional argument (text for encode/count, tokens for decode)
            result.positional = arg;
        }
    }

    return result;
}
