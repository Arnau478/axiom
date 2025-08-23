const std = @import("std");
const css = @import("css.zig");

pub const Integer = struct {
    value: isize,
};

pub const Number = struct {
    value: f32,
};

pub const Length = struct {
    magnitude: f32,
    unit: Unit,

    pub const Unit = enum {
        px,
    };

    pub const zero: Length = .{ .magnitude = 0, .unit = .px };

    pub fn toPx(length: Length) f32 {
        return switch (length.unit) {
            .px => length.magnitude,
        };
    }

    pub fn format(length: Length, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}{s}", .{ length.magnitude, @tagName(length.unit) });
    }
};

pub const Percentage = struct {
    value: f32,

    pub fn of(percentage: Percentage, value: f32) f32 {
        return value * (percentage.value / 100);
    }

    pub fn format(percentage: Percentage, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{d}%", .{percentage.value});
    }
};

pub const LengthPercentage = union(enum) {
    length: Length,
    percentage: Percentage,

    pub fn format(length_percentage: LengthPercentage, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        switch (length_percentage) {
            inline else => |v| try v.format(fmt, options, writer),
        }
    }
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn format(color: Color, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b });
    }
};

fn parseLength(source: []const u8, tokens: *[]const css.Token) ?Length {
    if (tokens.len > 0 and tokens.*[0].type == .dimension) {
        defer tokens.* = tokens.*[1..];
        const slice = tokens.*[0].slice(source);

        var magnitude_len: usize = 0;
        while (magnitude_len < slice.len and std.ascii.isDigit(slice[magnitude_len])) {
            magnitude_len += 1;
        }
        if (magnitude_len == 0 or magnitude_len == slice.len) return null;

        // TODO: Non-integers

        // TODO: 0 without unit

        const unit = inline for (comptime std.meta.fieldNames(Length.Unit)) |field| {
            if (std.mem.eql(u8, slice[magnitude_len..], field)) {
                break @field(Length.Unit, field);
            }
        } else {
            return null;
        };

        return .{
            .magnitude = std.fmt.parseFloat(f32, slice[0..magnitude_len]) catch return null,
            .unit = unit,
        };
    } else return null;
}

fn parsePercentage(source: []const u8, tokens: *[]const css.Token) ?Percentage {
    if (tokens.len > 0 and tokens.*[0].type == .percentage) {
        defer tokens.* = tokens.*[1..];
        const slice = tokens.*[0].slice(source);

        var number_len: usize = 0;
        while (number_len < slice.len and std.ascii.isDigit(slice[number_len])) {
            number_len += 1;
        }
        if (number_len == 0 or number_len == slice.len) return null;

        // TODO: Non-integers

        return .{
            .value = std.fmt.parseFloat(f32, slice[0..number_len]) catch return null,
        };
    } else return null;
}

fn parseColor(source: []const u8, tokens: *[]const css.Token) ?Color {
    if (tokens.len > 0 and tokens.*[0].type == .hash) {
        defer tokens.* = tokens.*[1..];
        const slice = tokens.*[0].slice(source);

        if (slice.len != 7 or slice[0] != '#') return null;

        return .{
            .r = std.fmt.parseInt(u8, slice[1..3], 16) catch return null,
            .g = std.fmt.parseInt(u8, slice[3..5], 16) catch return null,
            .b = std.fmt.parseInt(u8, slice[5..7], 16) catch return null,
        };
    } else return null;
}

fn parseKeyword(source: []const u8, tokens: *[]const css.Token, name: []const u8) ?void {
    if (tokens.len > 0 and tokens.*[0].type == .ident) {
        defer tokens.* = tokens.*[1..];
        const slice = tokens.*[0].slice(source);

        return if (std.mem.eql(u8, slice, name)) {} else null;
    } else return null;
}

fn parseField(comptime FieldType: type, comptime field_name: []const u8, source: []const u8, tokens: *[]const css.Token) ?FieldType {
    return switch (FieldType) {
        Length => parseLength(source, tokens) orelse return null,
        Percentage => parsePercentage(source, tokens) orelse return null,
        Color => parseColor(source, tokens) orelse return null,
        void => parseKeyword(source, tokens, field_name) orelse return null,
        else => switch (@typeInfo(FieldType)) {
            .@"struct" => v: {
                inline for (comptime std.meta.fieldNames(FieldType)) |struct_field| {
                    var value: FieldType = undefined;
                    @field(value, struct_field) = parseField(
                        @FieldType(FieldType, struct_field),
                        struct_field,
                        source,
                        tokens,
                    ) orelse return null;
                    break :v value;
                }
            },
            .@"union" => v: {
                inline for (comptime std.meta.fieldNames(FieldType)) |union_field| {
                    var t = tokens.*;
                    const res = parseField(
                        std.meta.FieldType(FieldType, @field(FieldType, union_field)),
                        union_field,
                        source,
                        &t,
                    ) orelse comptime continue;
                    break :v @unionInit(FieldType, union_field, res);
                } else {
                    return null;
                }
            },
            .@"enum" => v: {
                inline for (comptime std.meta.fieldNames(FieldType)) |enum_field| {
                    var t = tokens.*;
                    _ = parseField(
                        void,
                        enum_field,
                        source,
                        &t,
                    ) orelse comptime continue;
                    break :v @field(FieldType, enum_field);
                } else {
                    return null;
                }
            },
            else => @compileError("Invalid field type: " ++ @typeName(FieldType)),
        },
    };
}

pub fn parse(comptime T: type, source: []const u8, tokens: []const css.Token) ?T {
    std.debug.assert(@typeInfo(T) == .@"struct");

    var t = tokens;
    var value: T = undefined;

    inline for (comptime std.meta.fieldNames(T)) |field| {
        const FieldType = @TypeOf(@field(value, field));
        @field(value, field) = parseField(FieldType, field, source, &t) orelse return null;
    }

    return value;
}

test parse {
    const source = "2px #ff0000";

    var tokens = std.ArrayList(css.Token).init(std.testing.allocator);
    defer tokens.deinit();

    var iter = css.tokenIterator(source);

    while (iter.next()) |token| {
        try tokens.append(token);
    }

    const Value = struct {
        size: Length,
        color: Color,
    };

    const value = parse(Value, source, tokens.items).?;

    try std.testing.expectEqualDeep(Value{
        .size = .{ .magnitude = 2.0, .unit = .px },
        .color = .{ .r = 255, .g = 0, .b = 0 },
    }, value);
}

test "parse enum keywords" {
    const source = "hello-world";

    var tokens = std.ArrayList(css.Token).init(std.testing.allocator);
    defer tokens.deinit();

    var iter = css.tokenIterator(source);

    while (iter.next()) |token| {
        try tokens.append(token);
    }

    const Value = struct {
        value: enum {
            foo,
            bar,
            baz,
            @"hello-world",
        },
    };

    const value = parse(Value, source, tokens.items).?;

    try std.testing.expectEqualDeep(.@"hello-world", value.value);
}
