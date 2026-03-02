const std = @import("std");
const args_mod = @import("args.zig");
const commands = @import("commands.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var arg_iter = std.process.args();
    _ = arg_iter.skip(); // skip program name

    const parsed = args_mod.parseArgs(allocator, &arg_iter) catch |err| {
        const stderr = std.io.getStdErr().writer();
        switch (err) {
            args_mod.ParseError.UnknownCommand => try stderr.writeAll("error: unknown command. Run 'turbotoken help' for usage.\n"),
            args_mod.ParseError.UnknownFlag => try stderr.writeAll("error: unknown flag. Run 'turbotoken help' for usage.\n"),
            args_mod.ParseError.MissingValue => try stderr.writeAll("error: flag requires a value.\n"),
            else => try stderr.print("error: {}\n", .{err}),
        }
        std.process.exit(1);
    };

    runCommand(allocator, &parsed) catch |err| {
        const stderr = std.io.getStdErr().writer();
        switch (err) {
            error.EncodeFailed => try stderr.writeAll("error: encoding failed\n"),
            error.DecodeFailed => try stderr.writeAll("error: decoding failed\n"),
            error.CountFailed => try stderr.writeAll("error: count failed\n"),
            error.InvalidEncoding => try stderr.writeAll("error: unknown encoding name\n"),
            error.DownloadFailed => try stderr.writeAll("error: failed to download rank file\n"),
            error.AllocationFailed => try stderr.writeAll("error: allocation failed\n"),
            error.FileReadFailed => try stderr.writeAll("error: could not read file\n"),
            else => try stderr.print("error: {}\n", .{err}),
        }
        std.process.exit(1);
    };
}

fn runCommand(allocator: std.mem.Allocator, parsed: *const args_mod.ParsedArgs) !void {
    switch (parsed.command) {
        .encode => try commands.runEncode(allocator, parsed),
        .decode => try commands.runDecode(allocator, parsed),
        .count => try commands.runCount(allocator, parsed),
        .chat => try commands.runChat(allocator, parsed),
        .version => try commands.runVersion(parsed),
        .list_encodings => try commands.runListEncodings(parsed),
        .list_models => try commands.runListModels(parsed),
        .help => try commands.printHelp(),
    }
}
