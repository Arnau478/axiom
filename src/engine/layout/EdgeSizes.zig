const EdgeSizes = @This();

top: f32,
right: f32,
bottom: f32,
left: f32,

pub fn horizontal(edge_sizes: EdgeSizes) f32 {
    return edge_sizes.left + edge_sizes.right;
}

pub fn vertical(edge_sizes: EdgeSizes) f32 {
    return edge_sizes.top + edge_sizes.bottom;
}
