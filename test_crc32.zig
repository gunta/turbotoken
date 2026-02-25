const std = @import("std");

pub fn main() void {
    const key: u64 = 0x1234567890abcdef;
    var hash: u32 = 0;
    asm volatile (
        ".arch armv8-a+crc\n"
        ++ "crc32cx %w0, %w1, %x2"
        : [res] "=r" (hash)
        : [zero] "r" (@as(u32, 0)),
          [key] "r" (key)
    );
    std.debug.print("Hash: {}\n", .{hash});
}
