const BoxModel = @This();

const std = @import("std");
const engine = @import("../engine.zig");

pub const EdgeSizes = struct {
    top: f64,
    right: f64,
    bottom: f64,
    left: f64,

    pub fn expand(edge_sizes: EdgeSizes, rect: engine.Rect) engine.Rect {
        return .{
            .x = rect.x - edge_sizes.left,
            .y = rect.y - edge_sizes.top,
            .w = rect.w + edge_sizes.horizontal(),
            .h = rect.h + edge_sizes.vertical(),
        };
    }

    pub fn recess(edge_sizes: EdgeSizes, rect: engine.Rect) engine.Rect {
        // TODO: What should we do on underflow?
        return .{
            .x = rect.x + edge_sizes.left,
            .y = rect.y + edge_sizes.top,
            .w = rect.w - edge_sizes.horizontal(),
            .h = rect.h - edge_sizes.vertical(),
        };
    }

    pub fn add(self: EdgeSizes, other: EdgeSizes) EdgeSizes {
        return .{
            .top = self.top + other.top,
            .right = self.right + other.right,
            .bottom = self.bottom + other.bottom,
            .left = self.left + other.left,
        };
    }

    pub fn horizontal(edge_sizes: EdgeSizes) f64 {
        return edge_sizes.left + edge_sizes.right;
    }

    pub fn vertical(edge_sizes: EdgeSizes) f64 {
        return edge_sizes.top + edge_sizes.bottom;
    }
};

position: ?@Vector(2, f64),
box_width: ?f64,
box_height: ?f64,
padding: EdgeSizes,
border: EdgeSizes,
margin: EdgeSizes,

pub fn contentRect(box_model: BoxModel) ?engine.Rect {
    return box_model.padding.recess(box_model.paddingRect() orelse return null);
}

pub fn paddingRect(box_model: BoxModel) ?engine.Rect {
    return .{
        .x = (box_model.position orelse return null)[0],
        .y = (box_model.position orelse return null)[1],
        .w = box_model.box_width orelse return null,
        .h = box_model.box_height orelse return null,
    };
}

pub fn borderRect(box_model: BoxModel) ?engine.Rect {
    return box_model.border.expand(box_model.paddingRect() orelse return null);
}

pub fn marginRect(box_model: BoxModel) ?engine.Rect {
    return box_model.margin.expand(box_model.borderRect() orelse return null);
}

pub fn combinedPaddingBorder(box_model: BoxModel) EdgeSizes {
    return box_model.padding
        .add(box_model.border);
}

pub fn combinedBorderMargin(box_model: BoxModel) EdgeSizes {
    return box_model.border
        .add(box_model.margin);
}

pub fn combinedPaddingBorderMargin(box_model: BoxModel) EdgeSizes {
    return box_model.padding
        .add(box_model.border)
        .add(box_model.margin);
}
