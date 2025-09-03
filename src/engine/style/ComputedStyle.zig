const ComputedStyle = @This();

const style = @import("../style.zig");
const value = @import("value.zig");
const layout = @import("../layout.zig");
const Stylesheet = @import("Stylesheet.zig");

pub const Margin = union(enum) {
    length_percentage: value.LengthPercentage,
    auto,
};

margin_top: Margin,
margin_right: Margin,
margin_bottom: Margin,
margin_left: Margin,
border_top_width: value.Length,
border_right_width: value.Length,
border_bottom_width: value.Length,
border_left_width: value.Length,
padding_top: value.LengthPercentage,
padding_right: value.LengthPercentage,
padding_bottom: value.LengthPercentage,
padding_left: value.LengthPercentage,
width: ?value.LengthPercentage,
height: ?value.LengthPercentage,
display: layout.Display,
position: layout.Position,
background_color: value.Color,

pub fn applyDeclaration(computed_style: *ComputedStyle, declaration: Stylesheet.Rule.Style.Declaration) void {
    switch (declaration) {
        .margin => |margin| switch (margin.value) {
            .one => |v| {
                computed_style.applyDeclaration(.{ .@"margin-top" = v });
                computed_style.applyDeclaration(.{ .@"margin-right" = v });
                computed_style.applyDeclaration(.{ .@"margin-bottom" = v });
                computed_style.applyDeclaration(.{ .@"margin-left" = v });
            },
            else => @panic("TODO"),
        },
        .@"margin-top" => |v| computed_style.margin_top = switch (v.value) {
            .length_percentage => |length_percentage| .{ .length_percentage = length_percentage },
            .auto => .auto,
        },
        .@"margin-right" => |v| computed_style.margin_right = switch (v.value) {
            .length_percentage => |length_percentage| .{ .length_percentage = length_percentage },
            .auto => .auto,
        },
        .@"margin-bottom" => |v| computed_style.margin_bottom = switch (v.value) {
            .length_percentage => |length_percentage| .{ .length_percentage = length_percentage },
            .auto => .auto,
        },
        .@"margin-left" => |v| computed_style.margin_left = switch (v.value) {
            .length_percentage => |length_percentage| .{ .length_percentage = length_percentage },
            .auto => .auto,
        },
        .@"border-top-width" => |v| computed_style.border_top_width = switch (v.value) {
            .length => |length| length,
            .thin => .{ .magnitude = 1, .unit = .px },
            .medium => .{ .magnitude = 3, .unit = .px },
            .thick => .{ .magnitude = 5, .unit = .px },
        },
        .@"border-right-width" => |v| computed_style.border_right_width = switch (v.value) {
            .length => |length| length,
            .thin => .{ .magnitude = 1, .unit = .px },
            .medium => .{ .magnitude = 3, .unit = .px },
            .thick => .{ .magnitude = 5, .unit = .px },
        },
        .@"border-bottom-width" => |v| computed_style.border_bottom_width = switch (v.value) {
            .length => |length| length,
            .thin => .{ .magnitude = 1, .unit = .px },
            .medium => .{ .magnitude = 3, .unit = .px },
            .thick => .{ .magnitude = 5, .unit = .px },
        },
        .@"border-left-width" => |v| computed_style.border_left_width = switch (v.value) {
            .length => |length| length,
            .thin => .{ .magnitude = 1, .unit = .px },
            .medium => .{ .magnitude = 3, .unit = .px },
            .thick => .{ .magnitude = 5, .unit = .px },
        },
        .@"padding-top" => |v| computed_style.padding_top = v.value,
        .@"padding-right" => |v| computed_style.padding_right = v.value,
        .@"padding-bottom" => |v| computed_style.padding_bottom = v.value,
        .@"padding-left" => |v| computed_style.padding_left = v.value,
        .width => |v| computed_style.width = switch (v.value) {
            .length_percentage => |length_percentage| length_percentage,
            .auto => null,
        },
        .height => |v| computed_style.height = switch (v.value) {
            .length_percentage => |length_percentage| length_percentage,
            .auto => null,
        },
        .display => |v| computed_style.display = switch (v.value) {
            .@"inline" => .@"inline",
            .block => .block,
            .@"list-item" => .list_item,
            .@"inline-block" => .inline_block,
            .table => @panic("TODO"),
            .@"inline-table" => @panic("TODO"),
            .@"table-row_group" => @panic("TODO"),
            .@"table-header_group" => @panic("TODO"),
            .@"table-footer_group" => @panic("TODO"),
            .@"table-row" => @panic("TODO"),
            .@"table-column_group" => @panic("TODO"),
            .@"table-column" => @panic("TODO"),
            .@"table-cell" => @panic("TODO"),
            .@"table-caption" => @panic("TODO"),
            .none => .none,
        },
        .position => |v| computed_style.position = switch (v.value) {
            .static => .static,
            .relative => .relative,
            .absolute => .absolute,
            .fixed => .fixed,
        },
        .@"background-color" => |v| computed_style.background_color = v.value,
    }
}

pub fn flush(computed_style: *ComputedStyle) void {
    if (true) { // TODO: Border style
        computed_style.border_top_width = .zero;
        computed_style.border_right_width = .zero;
        computed_style.border_bottom_width = .zero;
        computed_style.border_left_width = .zero;
    }
}

pub const initial: ComputedStyle = .{
    .margin_top = .{ .length_percentage = .{ .length = .zero } },
    .margin_right = .{ .length_percentage = .{ .length = .zero } },
    .margin_bottom = .{ .length_percentage = .{ .length = .zero } },
    .margin_left = .{ .length_percentage = .{ .length = .zero } },
    .border_top_width = .{ .magnitude = 3, .unit = .px },
    .border_right_width = .{ .magnitude = 3, .unit = .px },
    .border_bottom_width = .{ .magnitude = 3, .unit = .px },
    .border_left_width = .{ .magnitude = 3, .unit = .px },
    .padding_top = .{ .length = .zero },
    .padding_right = .{ .length = .zero },
    .padding_bottom = .{ .length = .zero },
    .padding_left = .{ .length = .zero },
    .width = null,
    .height = null,
    .display = .@"inline",
    .position = .static,
    .background_color = value.Color.builtin.transparent,
};

pub fn inheritedOrInitial(computed_style: ComputedStyle) ComputedStyle {
    // TODO: Actually implement this
    return computed_style;
}
