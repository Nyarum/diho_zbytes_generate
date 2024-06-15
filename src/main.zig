const std = @import("std");
const encdec = @import("./encdec/encdec.zig");

const Test2 = struct {
    x: u32,

    pub inline fn tag(self: Test2, comptime T: type, comptime name: []const u8) ?encdec.Tag(T) {
        const caseString = enum { x };
        const case = std.meta.stringToEnum(caseString, name) orelse return null;
        switch (case) {
            .x => return tagx(self),
        }
    }

    inline fn tagx(self: Test2) encdec.Tag(u32) {
        _ = self; // autofix
        return encdec.Tag(u32){
            .isLittle = true,
            .fieldOption = encdec.FieldOption(u32){
                .isIgnore = false,
                .eq = encdec.FieldOptionEq(u32){
                    .eq = 16,
                },
            },
        };
    }
};

const Test = struct {
    x: u32,
    y: u32,
    angle: u32,
    angle_bu: [4]u32,
    internal_struct: Test2,
    testu8: u8 = 9,
    testu16: u16 = 10,

    fn comp_info() void {}
};

pub fn main() !void {
    const t = Test{
        .x = 1,
        .y = 2,
        .angle = 3,
        .angle_bu = .{ 4, 5, 6, 7 },
        .internal_struct = .{ .x = 4 },
    };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const res = try encdec.encode(Test, allocator, t, std.builtin.Endian.little);
    defer res.deinit();

    std.debug.print("Test 2 {x}\n", .{res.getData()});

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
