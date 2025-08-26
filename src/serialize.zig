const std = @import("std");

pub fn write(comptime T: type, value: T, writer: std.io.AnyWriter) !void {
    switch (T) {
        []const u8 => {
            try write(usize, value.len, writer);
            try writer.writeAll(value);
        },
        else => switch (@typeInfo(T)) {
            .pointer => |p| switch (p.size) {
                .slice => {
                    try write(usize, value.len, writer);
                    for (value) |v| {
                        try write(p.child, v, writer);
                    }
                },
                else => @compileError("Cannot serialize " ++ @typeName(T)),
            },
            .int => try writer.writeInt(T, value, .little),
            .@"struct" => |s| {
                inline for (s.fields) |field| {
                    try write(field.type, @field(value, field.name), writer);
                }
            },
            .@"union" => |u| {
                try write(u.tag_type.?, value, writer);
                switch (value) {
                    inline else => |v, field| {
                        try write(@FieldType(T, @tagName(field)), v, writer);
                    },
                }
            },
            .@"enum" => |e| {
                try write(e.tag_type, @intFromEnum(value), writer);
            },
            else => @compileError("Cannot serialize " ++ @typeName(T)),
        },
    }
}

pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: std.io.AnyReader) !T {
    return switch (T) {
        else => switch (@typeInfo(T)) {
            .pointer => |p| switch (p.size) {
                .slice => value: {
                    const size = try read(usize, allocator, reader);
                    const buf = try allocator.alloc(p.child, size);
                    errdefer allocator.free(buf);
                    for (buf) |*v| {
                        v.* = try read(p.child, allocator, reader);
                    }
                    break :value buf;
                },
                else => @compileError("Cannot serialize " ++ @typeName(T)),
            },
            .int => try reader.readInt(T, .little),
            .@"struct" => |s| value: {
                var value: T = undefined;
                inline for (s.fields) |field| {
                    @field(value, field.name) = try read(@FieldType(T, field.name), allocator, reader);
                }
                break :value value;
            },
            .@"union" => |u| value: {
                const tag = try read(u.tag_type.?, allocator, reader);
                switch (tag) {
                    inline else => |t| {
                        break :value @unionInit(T, @tagName(t), try read(@FieldType(T, @tagName(t)), allocator, reader));
                    },
                }
            },
            .@"enum" => |e| @enumFromInt(try read(e.tag_type, allocator, reader)),
            else => @compileError("Cannot serialize " ++ @typeName(T)),
        },
    };
}
