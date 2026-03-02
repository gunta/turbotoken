const std = @import("std");
const tt = @import("turbotoken");
const output = @import("output.zig");
const args_mod = @import("args.zig");

const ParsedArgs = args_mod.ParsedArgs;

fn resolveEncodingName(parsed: *const ParsedArgs) []const u8 {
    if (parsed.model_name) |model| {
        if (tt.modelToEncoding(model)) |enc| {
            return enc;
        }
    }
    return parsed.encoding_name;
}

fn loadRankBytes(allocator: std.mem.Allocator, parsed: *const ParsedArgs) ![]u8 {
    if (parsed.rank_file_path) |path| {
        return tt.rank_cache.readRankFileFromPath(allocator, path);
    }

    const enc_name = resolveEncodingName(parsed);

    if (parsed.no_download) {
        // Only try to read from cache, don't download
        const dir = tt.rank_cache.cacheDir(allocator) catch return tt.TurbotokenError.DownloadFailed;
        defer allocator.free(dir);
        const file_path = std.fmt.allocPrint(allocator, "{s}/{s}.tiktoken", .{ dir, enc_name }) catch return tt.TurbotokenError.AllocationFailed;
        defer allocator.free(file_path);
        return tt.rank_cache.readRankFileFromPath(allocator, file_path);
    }

    return tt.rank_cache.readRankFile(allocator, enc_name);
}

fn readInput(allocator: std.mem.Allocator, parsed: *const ParsedArgs) ![]u8 {
    if (parsed.positional) |text| {
        return allocator.dupe(u8, text) catch return tt.TurbotokenError.AllocationFailed;
    }

    if (parsed.file_path) |path| {
        return std.fs.cwd().readFileAlloc(allocator, path, 256 * 1024 * 1024) catch return tt.TurbotokenError.FileReadFailed;
    }

    // Read from stdin
    const stdin = std.io.getStdIn();
    return stdin.reader().readAllAlloc(allocator, 256 * 1024 * 1024) catch return tt.TurbotokenError.AllocationFailed;
}

pub fn runEncode(allocator: std.mem.Allocator, parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();

    const rank_bytes = try loadRankBytes(allocator, parsed);
    defer allocator.free(rank_bytes);

    const enc_name = resolveEncodingName(parsed);
    const spec = tt.getEncodingSpec(enc_name) orelse return tt.TurbotokenError.InvalidEncoding;
    const encoding = tt.Encoding{ .rank_payload = rank_bytes, .spec = spec };

    const text = try readInput(allocator, parsed);
    defer allocator.free(text);

    const tokens = try encoding.encode(allocator, text);
    defer allocator.free(tokens);

    try output.formatTokens(stdout, tokens, parsed.json_output);
}

pub fn runDecode(allocator: std.mem.Allocator, parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();

    const rank_bytes = try loadRankBytes(allocator, parsed);
    defer allocator.free(rank_bytes);

    const enc_name = resolveEncodingName(parsed);
    const spec = tt.getEncodingSpec(enc_name) orelse return tt.TurbotokenError.InvalidEncoding;
    const encoding = tt.Encoding{ .rank_payload = rank_bytes, .spec = spec };

    const input = try readInput(allocator, parsed);
    defer allocator.free(input);

    // Parse comma or space-separated token IDs
    var tokens = std.ArrayList(u32).init(allocator);
    defer tokens.deinit();

    var it = std.mem.tokenizeAny(u8, input, ", \t\n\r");
    while (it.next()) |tok_str| {
        if (tok_str.len == 0) continue;
        const val = std.fmt.parseInt(u32, tok_str, 10) catch {
            const stderr = std.io.getStdErr().writer();
            try stderr.print("error: invalid token ID: '{s}'\n", .{tok_str});
            return;
        };
        try tokens.append(val);
    }

    const decoded = try encoding.decode(allocator, tokens.items);
    defer allocator.free(decoded);

    try output.formatDecoded(stdout, decoded, parsed.json_output);
}

pub fn runCount(allocator: std.mem.Allocator, parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();

    const rank_bytes = try loadRankBytes(allocator, parsed);
    defer allocator.free(rank_bytes);

    const enc_name = resolveEncodingName(parsed);
    const spec = tt.getEncodingSpec(enc_name) orelse return tt.TurbotokenError.InvalidEncoding;
    const encoding = tt.Encoding{ .rank_payload = rank_bytes, .spec = spec };

    const text = try readInput(allocator, parsed);
    defer allocator.free(text);

    const count_val = try encoding.count(text);

    try output.formatCount(stdout, count_val, parsed.json_output);
}

pub fn runChat(allocator: std.mem.Allocator, parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();

    const rank_bytes = try loadRankBytes(allocator, parsed);
    defer allocator.free(rank_bytes);

    const enc_name = resolveEncodingName(parsed);
    const spec = tt.getEncodingSpec(enc_name) orelse return tt.TurbotokenError.InvalidEncoding;
    const encoding = tt.Encoding{ .rank_payload = rank_bytes, .spec = spec };

    // Read JSON messages from stdin
    const stdin = std.io.getStdIn();
    const input = stdin.reader().readAllAlloc(allocator, 256 * 1024 * 1024) catch return tt.TurbotokenError.AllocationFailed;
    defer allocator.free(input);

    // Parse JSON array of {role, content} objects
    const parsed_json = std.json.parseFromSlice([]const struct {
        role: []const u8,
        content: []const u8,
    }, allocator, input, .{ .allocate = .alloc_always }) catch {
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll("error: invalid JSON input. Expected: [{\"role\":\"...\",\"content\":\"...\"},...]\n");
        return;
    };
    defer parsed_json.deinit();

    const msgs = parsed_json.value;
    var chat_messages = allocator.alloc(tt.ChatMessage, msgs.len) catch return tt.TurbotokenError.AllocationFailed;
    defer allocator.free(chat_messages);

    for (msgs, 0..) |msg, i| {
        chat_messages[i] = .{
            .role = msg.role,
            .content = msg.content,
        };
    }

    const tokens = try encoding.encodeChat(allocator, chat_messages, .{});
    defer allocator.free(tokens);

    try output.formatTokens(stdout, tokens, parsed.json_output);
}

pub fn runVersion(parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();
    try output.formatVersion(stdout, "0.1.0-dev", parsed.json_output);
}

pub fn runListEncodings(parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();
    const names = tt.listEncodingNames();

    if (parsed.json_output) {
        try stdout.writeByte('[');
        for (names, 0..) |name, i| {
            if (i > 0) try stdout.writeAll(", ");
            try stdout.print("\"{s}\"", .{name});
        }
        try stdout.writeAll("]\n");
    } else {
        for (names) |name| {
            try stdout.print("{s}\n", .{name});
        }
    }
}

pub fn runListModels(parsed: *const ParsedArgs) !void {
    const stdout = std.io.getStdOut().writer();

    const ModelEntry = struct {
        model: []const u8,
        encoding: []const u8,
    };

    const models: []const ModelEntry = &.{
        .{ .model = "o1", .encoding = "o200k_base" },
        .{ .model = "o3", .encoding = "o200k_base" },
        .{ .model = "o4-mini", .encoding = "o200k_base" },
        .{ .model = "gpt-5", .encoding = "o200k_base" },
        .{ .model = "gpt-4.1", .encoding = "o200k_base" },
        .{ .model = "gpt-4o", .encoding = "o200k_base" },
        .{ .model = "gpt-4o-mini", .encoding = "o200k_base" },
        .{ .model = "gpt-4.1-mini", .encoding = "o200k_base" },
        .{ .model = "gpt-4.1-nano", .encoding = "o200k_base" },
        .{ .model = "gpt-oss-120b", .encoding = "o200k_harmony" },
        .{ .model = "gpt-4", .encoding = "cl100k_base" },
        .{ .model = "gpt-3.5-turbo", .encoding = "cl100k_base" },
        .{ .model = "gpt-3.5", .encoding = "cl100k_base" },
        .{ .model = "davinci-002", .encoding = "cl100k_base" },
        .{ .model = "babbage-002", .encoding = "cl100k_base" },
        .{ .model = "text-davinci-003", .encoding = "p50k_base" },
        .{ .model = "text-davinci-002", .encoding = "p50k_base" },
        .{ .model = "text-davinci-001", .encoding = "r50k_base" },
        .{ .model = "davinci", .encoding = "r50k_base" },
        .{ .model = "gpt2", .encoding = "gpt2" },
    };

    if (parsed.json_output) {
        try stdout.writeAll("[\n");
        for (models, 0..) |entry, i| {
            if (i > 0) try stdout.writeAll(",\n");
            try stdout.print("  {{\"model\": \"{s}\", \"encoding\": \"{s}\"}}", .{ entry.model, entry.encoding });
        }
        try stdout.writeAll("\n]\n");
    } else {
        for (models) |entry| {
            try stdout.print("{s:<30} {s}\n", .{ entry.model, entry.encoding });
        }
    }
}

pub fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\turbotoken - the fastest BPE tokenizer on every platform
        \\
        \\USAGE:
        \\  turbotoken <command> [OPTIONS] [TEXT]
        \\
        \\COMMANDS:
        \\  encode          Encode text to token IDs
        \\  decode          Decode token IDs to text
        \\  count           Count tokens in text
        \\  chat            Encode chat messages (JSON from stdin)
        \\  version         Show version
        \\  list-encodings  List available encodings
        \\  list-models     List model-to-encoding mappings
        \\  help            Show this help
        \\
        \\OPTIONS:
        \\  -e, --encoding NAME   Encoding name (default: o200k_base)
        \\  -m, --model NAME      Infer encoding from model name
        \\  --json                Output as JSON
        \\  -f, --file PATH       Read input from file
        \\  --rank-file PATH      Explicit rank file path
        \\  --no-download         Error if rank file not cached
        \\
        \\EXAMPLES:
        \\  turbotoken encode "Hello, world!"
        \\  turbotoken count -f document.txt
        \\  turbotoken decode "9906 11 1917"
        \\  echo "Hello" | turbotoken count
        \\  turbotoken encode -m gpt-4o "Hello, world!" --json
        \\  echo '[{"role":"user","content":"Hi"}]' | turbotoken chat
        \\
    );
}
