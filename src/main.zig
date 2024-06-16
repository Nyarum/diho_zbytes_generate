const std = @import("std");
pub const encdec = @import("./encdec/encdec.zig");

const Test2 = struct {
    x: u32 = 0,
    y: u8 = 0,
    str: encdec.String = encdec.String{},
    arrayTest: [2]u8 = .{ 0, 0 },

    pub inline fn tag(self: Test2, comptime T: type, comptime name: []const u8) ?encdec.Tag(T) {
        if (std.mem.eql(u8, name, "x") and T == u32) {
            return tagx(self);
        }

        return null;
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
    name: encdec.String = encdec.String{ .value = "hello" },
    testu162: u16 = 11,

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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const res = try encdec.encode(allocator, t, std.builtin.Endian.big);
    defer res.deinit();

    std.debug.print("Test 2 {x}\n", .{res.getData()});

    const test2 = try allocator.create(Test2);
    defer allocator.destroy(test2);

    const buffer = try encdec.Buffer.initWithBuf(allocator, &[_]u8{ 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x04, 0x68, 0x65, 0x6c, 0x00, 0x01, 0x02 });
    defer buffer.deinit();

    try encdec.decode(Test2, test2, buffer, std.builtin.Endian.big);

    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("Test 2. {any}\n", .{test2});
}
