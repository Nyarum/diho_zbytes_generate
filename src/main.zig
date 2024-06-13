const std = @import("std");

const Test2 = struct {
    x: u32,
};

const Test = struct {
    x: u32,
    y: u32,
    angle: u32,
    angle_bu: [4]u32,
    internal_struct: Test2,

    fn comp_info() void {}
};

const Buffer = struct {
    data: []u8,
    comptime pos: comptime_int = 0,

    fn init(allocator: std.mem.Allocator) !Buffer {
        return Buffer{ .data = try allocator.alloc(u8, 2048) };
    }

    fn writeInt(self: *Buffer, comptime T: type, comptime pos: usize, value: T, endian: std.builtin.Endian) void {
        std.mem.writeInt(T, self.data[pos .. pos + @sizeOf(T)], value, endian);
    }
};

inline fn encode_array_value(comptime T: type, pkt: T, comptime value_name: []const u8, arr_type: type, comptime pos: usize, buffer: *Buffer, endian: std.builtin.Endian) usize {
    comptime var pos_new: usize = pos;

    inline for (@field(pkt, value_name)) |arr_value| {
        switch (@typeInfo(arr_type)) {
            .Int => {
                buffer.writeInt(arr_type, pos_new, arr_value, endian);
                pos_new += @sizeOf(arr_type);
            },
            .Struct => {
                const struct_size = encode_struct(arr_type, buffer, pos_new, arr_value, endian);
                pos_new += struct_size;
            },
            else => {
                @compileError("Unsupported type: " ++ @typeName(arr_type));
            },
        }
    }

    return pos_new;
}

inline fn encode_struct(comptime T: type, buffer: *Buffer, comptime init_pos: usize, packet: T, endian: std.builtin.Endian) usize {
    comptime var pos: usize = init_pos;

    inline for (std.meta.fields(T)) |value| {
        std.debug.print("{any}\n", .{value});

        // Handle array cases
        switch (@typeInfo(value.type)) {
            .Int => {
                buffer.writeInt(value.type, pos, @field(packet, value.name), endian);
                pos += @sizeOf(value.type);
            },
            .Array => |arr| {
                const arr_size = encode_array_value(T, packet, value.name, arr.child, pos, buffer, endian);
                pos = arr_size;
            },
            .Struct => {
                const new_pos = encode_struct(value.type, buffer, pos, @field(packet, value.name), endian);
                pos = new_pos;
            },
            else => {},
        }
    }

    return pos;
}

fn encode(comptime T: type, allocator: std.mem.Allocator, packet: T, endian: std.builtin.Endian) ![]u8 {
    var buffer = try Buffer.init(allocator);

    std.debug.print("slice len {any}\n", .{buffer.pos});

    _ = encode_struct(T, &buffer, 0, packet, endian);

    std.debug.print("Test 2 {x}\n", .{buffer.data});

    return buffer.data;
}

pub fn main() !void {
    const t = Test{ .x = 1, .y = 2, .angle = 3, .angle_bu = .{ 4, 5, 6, 7 }, .internal_struct = .{ .x = 4 } };

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const res = try encode(Test, allocator, t, std.builtin.Endian.little);
    _ = res; // autofix
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
