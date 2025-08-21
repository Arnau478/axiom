const ComputedStyle = @This();

const Stylesheet = @import("Stylesheet.zig");

margin_top: Stylesheet.Rule.Style.Declaration.Property.@"margin-top".Value() = .initial,
margin_right: Stylesheet.Rule.Style.Declaration.Property.@"margin-right".Value() = .initial,
margin_bottom: Stylesheet.Rule.Style.Declaration.Property.@"margin-bottom".Value() = .initial,
margin_left: Stylesheet.Rule.Style.Declaration.Property.@"margin-left".Value() = .initial,
display: Stylesheet.Rule.Style.Declaration.Property.display.Value() = .initial,

pub fn inheritedOrInitial(computed_style: ComputedStyle) ComputedStyle {
    _ = computed_style;

    return .{
        .margin_top = .initial,
        .margin_right = .initial,
        .margin_bottom = .initial,
        .margin_left = .initial,
        .display = .initial,
    };
}
