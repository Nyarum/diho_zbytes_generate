const std = @import("std");

pub inline fn FieldOptionEq(comptime T: type) type {
    return union(enum) {
        eq: T,
        notEq: T,
    };
}

pub inline fn FieldOption(comptime T: type) type {
    return struct {
        isIgnore: bool,
        eq: ?FieldOptionEq(T),
    };
}

pub inline fn Tag(comptime T: type) type {
    return struct { isLittle: bool, fieldOption: FieldOption(T) };
}

const Buffer = struct {
    allocator: std.mem.Allocator,
    data: []u8,
    pos: usize = 0,

    fn init(allocator: std.mem.Allocator) !Buffer {
        return Buffer{ .allocator = allocator, .data = try allocator.alloc(u8, 2048) };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.data);
    }

    fn writeInt(self: *Buffer, comptime T: type, value: T, endian: std.builtin.Endian) void {
        switch (T) {
            u8 => {
                var writeData: [1]u8 = undefined;
                std.mem.writeInt(T, &writeData, value, endian);

                self.data[self.pos] = writeData[0];
                self.pos += 1;
            },
            u16 => {
                var writeData: [2]u8 = undefined;
                std.mem.writeInt(T, &writeData, value, endian);

                self.data[self.pos] = writeData[0];
                self.data[self.pos + 1] = writeData[1];
                self.pos += 2;
            },
            u32 => {
                var writeData: [4]u8 = undefined;
                std.mem.writeInt(T, &writeData, value, endian);

                self.data[self.pos] = writeData[0];
                self.data[self.pos + 1] = writeData[1];
                self.data[self.pos + 2] = writeData[2];
                self.data[self.pos + 3] = writeData[3];
                self.pos += 4;
            },
            else => {},
        }
    }

    pub fn getData(self: *Buffer) []u8 {
        return self.data[0..self.pos];
    }
};

inline fn encode_array_value(
    comptime T: type,
    pkt: T,
    comptime value_name: []const u8,
    arr_type: type,
    buffer: *Buffer,
    endian: std.builtin.Endian,
) void {
    inline for (@field(pkt, value_name)) |arr_value| {
        switch (@typeInfo(arr_type)) {
            .Int => {
                buffer.writeInt(arr_type, arr_value, endian);
            },
            .Struct => {
                encode_struct(arr_type, buffer, arr_value, endian);
            },
            else => {
                @compileError("Unsupported type: " ++ @typeName(arr_type));
            },
        }
    }
}

fn encode_struct_runtime(comptime T: type, value: anytype, buffer: *Buffer, packet: anytype, endian_new: std.builtin.Endian) void {
    switch (@typeInfo(value.type)) {
        .Int => {
            buffer.writeInt(value.type, @field(packet, value.name), endian_new);
        },
        .Array => |arr| {
            encode_array_value(T, packet, value.name, arr.child, buffer, endian_new);
        },
        .Struct => {
            encode_struct(value.type, buffer, @field(packet, value.name), endian_new);
        },
        else => {},
    }
}

inline fn encode_struct(
    comptime T: type,
    buffer: *Buffer,
    packet: T,
    endian: std.builtin.Endian,
) void {
    var endian_new = endian;

    inline for (std.meta.fields(T)) |value| {
        std.debug.print("{any}\n", .{value});

        if (std.meta.hasFn(T, "tag")) {
            const tag = packet.tag(value.type, value.name);

            if (tag) |t| {
                if (t.isLittle) {
                    endian_new = std.builtin.Endian.little;
                }

                if (!t.fieldOption.isIgnore) {
                    encode_struct_runtime(T, value, buffer, packet, endian_new);
                }
            }
        } else {
            encode_struct_runtime(T, value, buffer, packet, endian_new);
        }
    }
}

pub fn encode(comptime T: type, allocator: std.mem.Allocator, packet: T, endian: std.builtin.Endian) !*Buffer {
    var buffer = try Buffer.init(allocator);
    errdefer buffer.deinit(allocator);

    encode_struct(T, &buffer, packet, endian);

    return &buffer;
}
