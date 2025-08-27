const engine = @import("engine");

pub const Request = union(enum(u8)) {
    navigate_to_url: []const u8,
    resize_viewport: struct {
        width: usize,
        height: usize,
    },
    activate,
};

pub const Response = union(enum(u8)) {
    new_frame: []const engine.render.Command,
};
