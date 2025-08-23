const ComputedStyle = @This();

const style = @import("../style.zig");
const value = @import("value.zig");
const Stylesheet = @import("Stylesheet.zig");

margin_top: Stylesheet.Rule.Style.Declaration.Property.@"margin-top".Value() = .initial,
margin_right: Stylesheet.Rule.Style.Declaration.Property.@"margin-right".Value() = .initial,
margin_bottom: Stylesheet.Rule.Style.Declaration.Property.@"margin-bottom".Value() = .initial,
margin_left: Stylesheet.Rule.Style.Declaration.Property.@"margin-left".Value() = .initial,
border_top_width: value.Length = Stylesheet.Rule.Style.Declaration.Property.@"border-top-width".Value().initial.compute(),
border_right_width: value.Length = Stylesheet.Rule.Style.Declaration.Property.@"border-right-width".Value().initial.compute(),
border_bottom_width: value.Length = Stylesheet.Rule.Style.Declaration.Property.@"border-bottom-width".Value().initial.compute(),
border_left_width: value.Length = Stylesheet.Rule.Style.Declaration.Property.@"border-left-width".Value().initial.compute(),
padding_top: Stylesheet.Rule.Style.Declaration.Property.@"padding-top".Value() = .initial,
padding_right: Stylesheet.Rule.Style.Declaration.Property.@"padding-right".Value() = .initial,
padding_bottom: Stylesheet.Rule.Style.Declaration.Property.@"padding-bottom".Value() = .initial,
padding_left: Stylesheet.Rule.Style.Declaration.Property.@"padding-left".Value() = .initial,
width: Stylesheet.Rule.Style.Declaration.Property.width.Value() = .initial,
height: Stylesheet.Rule.Style.Declaration.Property.height.Value() = .initial,
display: Stylesheet.Rule.Style.Declaration.Property.display.Value() = .initial,

pub fn flush(computed_style: *ComputedStyle) void {
    if (true) { // TODO: Border style
        computed_style.border_top_width = .zero;
        computed_style.border_right_width = .zero;
        computed_style.border_bottom_width = .zero;
        computed_style.border_left_width = .zero;
    }
}
