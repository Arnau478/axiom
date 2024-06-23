const Stylesheet = @This();

location: ?[]const u8,
value: []const Rule,

pub const Rule = struct {
    selectors: []const Selector,
    declarations: []const Declaration,

    pub const Selector = union(enum) {
        simple: Simple,

        pub const Simple = struct {
            element_name: ?[]const u8,
            id: ?[]const u8,
            class: []const []const u8,
        };
    };

    pub const Declaration = struct {
        property: []const u8,
        value: Value,
    };
};

pub const Value = union(enum) {
    color: Color,

    pub const Color = struct {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };
};
