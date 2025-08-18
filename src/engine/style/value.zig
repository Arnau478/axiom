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
};

pub const Percentage = struct {
    value: f32,
};

pub const LengthPercentage = union(enum) {
    length: Length,
    percentage: Percentage,
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
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

fn parseField(comptime FieldType: type, source: []const u8, tokens: *[]const css.Token) ?FieldType {
    return switch (FieldType) {
        Length => parseLength(source, tokens) orelse return null,
        Percentage => parsePercentage(source, tokens) orelse return null,
        Color => parseColor(source, tokens) orelse return null,
        else => switch (@typeInfo(FieldType)) {
            .@"union" => v: {
                inline for (comptime std.meta.fieldNames(FieldType)) |union_field| {
                    const res = parseField(
                        std.meta.FieldType(FieldType, @field(FieldType, union_field)),
                        source,
                        tokens,
                    ) orelse comptime continue;
                    break :v @unionInit(FieldType, union_field, res);
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
        @field(value, field) = parseField(FieldType, source, &t) orelse return null;
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
