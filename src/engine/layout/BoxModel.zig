const Box = @This();

const EdgeSizes = @import("EdgeSizes.zig");
const Rect = @import("Rect.zig");

content_box: Rect,
padding: EdgeSizes,
border: EdgeSizes,
margin: EdgeSizes,

pub fn paddingBox(box: Box) Rect {
    return box.content_box.expand(box.padding);
}

pub fn borderBox(box: Box) Rect {
    return box.paddingBox().expand(box.border);
}

pub fn marginBox(box: Box) Rect {
    return box.borderBox().expand(box.margin);
}
