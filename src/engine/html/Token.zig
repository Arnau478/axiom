const Token = @This();

type: Type,

pub const Type = union(enum) {
    doctype: Doctype,
    start_tag: Tag,
    end_tag: Tag,
    comment: Span,
    character: Span,

    pub const Doctype = struct {
        name: ?Span = null,
        public: ?Span = null,
        system: ?Span = null,
        force_quirks: bool = false,
    };

    pub const Tag = struct {
        name: Span,
        self_closing: bool = false,
    };
};

pub const Span = struct {
    start: usize,
    end: usize,

    pub const empty: Span = .{ .start = 0, .end = 0 };

    pub fn slice(span: Span, source: []const u8) []const u8 {
        return source[span.start..span.end];
    }
};
