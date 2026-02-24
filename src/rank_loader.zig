const std = @import("std");

pub const RankTable = struct {
    items: std.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) RankTable {
        return .{ .items = std.ArrayList(u32).init(allocator) };
    }

    pub fn deinit(self: *RankTable) void {
        self.items.deinit();
    }
};

pub fn loadFromBytes(_: std.mem.Allocator, _: []const u8) !RankTable {
    return error.NotImplemented;
}
