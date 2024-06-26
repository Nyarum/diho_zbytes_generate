const std = @import("std");

pub const String = struct {
    value: []const u8 = "",
};

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

pub const Buffer = struct {
    allocator: std.mem.Allocator,
    data: []u8,
    pos: usize = 0,

    fn init(allocator: std.mem.Allocator) !*Buffer {
        const buffer = try allocator.create(Buffer);
        buffer.data = try allocator.alloc(u8, 2048);
        buffer.pos = 0;
        buffer.allocator = allocator;

        return buffer;
    }

    pub fn initWithBuf(allocator: std.mem.Allocator, data: []const u8) !*Buffer {
        const buffer = try allocator.create(Buffer);
        buffer.data = try allocator.alloc(u8, data.len);
        buffer.pos = 0;
        buffer.allocator = allocator;

        @memcpy(buffer.data, data);

        return buffer;
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.data);
        self.allocator.destroy(self);
    }

    fn read(self: *Buffer, comptime T: type, endian: std.builtin.Endian) T {
        switch (T) {
            u8 => {
                const res = self.data[self.pos];
                self.pos += 1;
                return res;
            },
            u16 => {
                var readBuf: [2]u8 = undefined;
                @memcpy(&readBuf, self.data[self.pos .. self.pos + 2]);
                const readData = std.mem.readInt(T, &readBuf, endian);
                self.pos += 2;
                return readData;
            },
            u32 => {
                var readBuf: [4]u8 = undefined;
                @memcpy(&readBuf, self.data[self.pos .. self.pos + 4]);
                const readData = std.mem.readInt(T, &readBuf, endian);
                self.pos += 4;
                return readData;
            },
            []const u8 => {
                const len = self.read(u16, std.builtin.Endian.big);
                std.debug.print("current len {any} and {any}\n", .{ len, self.pos });

                const readData = self.data[self.pos .. self.pos + len];
                self.pos += len;

                return readData[0 .. len - 1];
            },
            else => {},
        }
    }

    fn write(self: *Buffer, comptime T: type, value: T, endian: std.builtin.Endian) void {
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
            []const u8 => {
                self.write(u16, @intCast(value.len + 1), endian);

                std.mem.copyForwards(u8, self.data[self.pos..], value);
                self.pos += value.len;

                std.mem.copyForwards(u8, self.data[self.pos..], &[_]u8{0x00});
                self.pos += 1;
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
                buffer.write(arr_type, arr_value, endian);
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
            buffer.write(value.type, @field(packet, value.name), endian_new);
        },
        .Array => |arr| {
            encode_array_value(T, packet, value.name, arr.child, buffer, endian_new);
        },
        .Struct => {
            if (value.type == String) {
                buffer.write([]const u8, @field(packet, value.name).value, endian_new);
                return;
            }

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

pub fn encode(allocator: std.mem.Allocator, packet: anytype, endian: std.builtin.Endian) !*Buffer {
    var buffer = try Buffer.init(allocator);
    errdefer buffer.deinit(allocator);

    encode_struct(@TypeOf(packet), buffer, packet, endian);

    return buffer;
}

inline fn decode_array_value(
    pkt: anytype,
    comptime value_name: []const u8,
    arr_type: type,
    buffer: *Buffer,
    endian: std.builtin.Endian,
) void {
    comptime var i = 0;

    inline for (@field(pkt, value_name)) |arr_value| {
        _ = arr_value; // autofix
        switch (@typeInfo(arr_type)) {
            .Int => {
                const resInt = buffer.read(arr_type, endian);
                @field(pkt, value_name)[i] = resInt;
                i += 1;
            },
            .Struct => {
                decode_struct(arr_type, buffer, endian);
            },
            else => {
                @compileError("Unsupported type: " ++ @typeName(arr_type));
            },
        }
    }
}

fn decode_struct_runtime(value: anytype, buffer: *Buffer, packet: anytype, endian_new: std.builtin.Endian) void {
    switch (@typeInfo(value.type)) {
        .Int => {
            const resInt = buffer.read(value.type, endian_new);
            std.debug.print("int res: {any}\n", .{resInt});
            @field(packet, value.name) = resInt;
        },
        .Array => |arr| {
            decode_array_value(packet, value.name, arr.child, buffer, endian_new);
        },
        .Struct => {
            if (value.type == String) {
                const resString = buffer.read([]const u8, endian_new);
                @field(packet, value.name).value = resString;
                return;
            }

            decode_struct(value, buffer, endian_new);
        },
        else => {},
    }
}

inline fn decode_struct(
    comptime T: type,
    packet: anytype,
    buffer: *Buffer,
    endian: std.builtin.Endian,
) !void {
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
                    decode_struct_runtime(value, buffer, packet, endian_new);
                }
            } else {
                decode_struct_runtime(value, buffer, packet, endian_new);
            }
        } else {
            decode_struct_runtime(value, buffer, packet, endian_new);
        }
    }
}

pub fn decode(comptime T: type, packet: anytype, buffer: *Buffer, endian: std.builtin.Endian) !void {
    try decode_struct(T, packet, buffer, endian);
}
