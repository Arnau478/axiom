const TreeConstructor = @This();

const std = @import("std");
const Dom = @import("../Dom.zig");
const Token = @import("Token.zig");
const Tokenizer = @import("Tokenizer.zig");

allocator: std.mem.Allocator,
dom: *Dom,
document_id: Dom.DocumentId,
insertion_mode: InsertionMode,
original_insertion_mode: ?InsertionMode,
scripting_enabled: bool,
frameset_ok: bool,
open_elements: std.ArrayListUnmanaged(Dom.ElementId),
head: ?Dom.ElementId,

pub fn init(allocator: std.mem.Allocator, dom: *Dom, document_id: Dom.DocumentId) TreeConstructor {
    return .{
        .allocator = allocator,
        .dom = dom,
        .document_id = document_id,
        .insertion_mode = .initial,
        .original_insertion_mode = null,
        .scripting_enabled = true,
        .frameset_ok = true,
        .open_elements = .empty,
        .head = null,
    };
}

pub fn deinit(tree_constructor: *TreeConstructor) void {
    tree_constructor.open_elements.deinit(tree_constructor.allocator);
}

pub const InsertionMode = enum {
    initial,
    before_html,
    before_head,
    in_head,
    in_head_noscript,
    after_head,
    in_body,
    text,
    in_table,
    in_table_text,
    in_caption,
    in_column_group,
    in_table_body,
    in_row,
    in_cell,
    in_template,
    after_body,
    in_frameset,
    after_frameset,
    after_after_body,
    after_after_frameset,
};

fn currentElement(tree_constructor: TreeConstructor) ?Dom.ElementId {
    return tree_constructor.open_elements.getLastOrNull();
}

fn createElementForToken(tree_constructor: TreeConstructor, source: []const u8, token: ?Token) !Dom.ElementId {
    const local_name = token.?.type.start_tag.name.slice(source);

    // TODO "is" attribute
    // TODO: Custom element registry
    // TODO: Custom element definition

    const element = try tree_constructor.dom.createElement(local_name);

    var attribute_iter = token.?.type.start_tag.attributeIterator();
    while (attribute_iter.next(source)) |attribute| {
        const attribute_id = try tree_constructor.dom.createAttribute(
            attribute.name.slice(source),
            (attribute.value orelse @panic("TODO")).slice(source),
        );
        try tree_constructor.dom.addAttribute(element, attribute_id);
    }

    // TODO: "xmlns" attribute
    // TODO: Resetable elements (except form-associated custom elements)
    // TODO: Form-associated non-custom elements

    return element;
}

fn insertElementForToken(tree_constructor: *TreeConstructor, source: []const u8, token: ?Token) !Dom.ElementId {
    const element = try tree_constructor.createElementForToken(source, token);

    // TODO: Proper insertion position
    try tree_constructor.dom.appendChild(tree_constructor.currentElement().?, .{ .element = element });

    try tree_constructor.open_elements.append(tree_constructor.allocator, element);

    return element;
}

fn insertCharacter(tree_constructor: *TreeConstructor, data: []const u8) !void {
    std.debug.assert(data.len > 0);
    std.debug.assert(std.unicode.utf8ByteSequenceLength(data[0]) catch 0 == 1);

    if (tree_constructor.dom.getElement(tree_constructor.currentElement().?).?.children.getLastOrNull()) |last| {
        if (last == .text) {
            // TODO: Append to last text node
            const str = try std.mem.join(tree_constructor.allocator, "", &.{ tree_constructor.dom.getText(last.text).?.data, data });
            defer tree_constructor.allocator.free(str);
            tree_constructor.dom.getText(last.text).?.data = try tree_constructor.dom.internString(str);
            return;
        }
    }

    try tree_constructor.dom.appendChild(
        tree_constructor.currentElement().?,
        .{ .text = try tree_constructor.dom.createText(data) },
    );
}

fn reconstructActiveFormattingElements(tree_constructor: *TreeConstructor) void {
    _ = tree_constructor;
    // TODO
}

fn generateImpliedEndTagsExcept(tree_constructor: *TreeConstructor, exception: ?[]const u8) void {
    while (tree_constructor.currentElement() != null) {
        var match = false;
        inline for (&.{ "dd", "dt", "li", "optgroup", "option", "p", "rb", "rp", "rt", "rtc" }) |name| {
            if (exception != null and std.mem.eql(u8, name, exception.?)) comptime continue;
            if (std.mem.eql(u8, tree_constructor.dom.getElement(tree_constructor.currentElement().?).?.tag_name, name)) {
                match = true;
            }
        }

        if (match) {
            _ = tree_constructor.open_elements.pop().?;
        } else {
            return;
        }
    }
}

fn hasElementInSpecificScope(tree_constructor: TreeConstructor, name: []const u8, scope: []const []const u8) bool {
    var i: usize = 0;
    while (true) {
        const node = tree_constructor.open_elements.items[tree_constructor.open_elements.items.len - 1 - i];

        if (std.mem.eql(u8, tree_constructor.dom.getElement(node).?.tag_name, name)) {
            return true;
        } else {
            for (scope) |scope_element| {
                if (std.mem.eql(u8, tree_constructor.dom.getElement(node).?.tag_name, scope_element)) {
                    return false;
                }
            }

            i += 1;
        }
    }
}

fn hasElementInScope(tree_constructor: TreeConstructor, name: []const u8) bool {
    // TODO: MathML and SVG

    return tree_constructor.hasElementInSpecificScope(name, &.{ "applet", "caption", "html", "table", "td", "th", "marquee", "object", "select", "template" });
}

fn isSpecialCategoryTagName(name: []const u8) bool {
    // TODO: MathML and SVG
    inline for (&.{
        "address",
        "applet",
        "area",
        "article",
        "aside",
        "base",
        "basefont",
        "bgsound",
        "blockquote",
        "body",
        "br",
        "button",
        "caption",
        "center",
        "col",
        "colgroup",
        "dd",
        "details",
        "dir",
        "div",
        "dl",
        "dt",
        "embed",
        "fieldset",
        "figcaption",
        "figure",
        "footer",
        "form",
        "frame",
        "frameset",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "head",
        "header",
        "hgroup",
        "hr",
        "html",
        "iframe",
        "img",
        "input",
        "keygen",
        "li",
        "link",
        "listing",
        "main",
        "marquee",
        "menu",
        "meta",
        "nav",
        "noembed",
        "noframes",
        "noscript",
        "object",
        "ol",
        "p",
        "param",
        "plaintext",
        "pre",
        "script",
        "search",
        "section",
        "select",
        "source",
        "style",
        "summary",
        "table",
        "tbody",
        "td",
        "template",
        "textarea",
        "tfoot",
        "th",
        "thead",
        "title",
        "tr",
        "track",
        "ul",
        "wbr",
        "xmp",
    }) |special| {
        if (std.mem.eql(u8, name, special)) return true;
    }

    return false;
}

fn isEof(token: ?Token) bool {
    return token == null;
}

fn isCharacterToken(token: ?Token) bool {
    return token != null and token.?.type == .character;
}

fn isNullCharacterToken(token: ?Token, source: []const u8) bool {
    return isCharacterToken(token) and std.mem.eql(u8, token.?.type.character.slice(source), &.{0});
}

fn isWhitespaceCharacterToken(token: ?Token, source: []const u8) bool {
    return isCharacterToken(token) and switch (token.?.type.character.slice(source)[0]) {
        '\t', '\n', 0x0c, '\r', ' ' => true,
        else => false,
    };
}

fn isCommentToken(token: ?Token) bool {
    return token != null and token.?.type == .comment;
}

fn isDoctypeToken(token: ?Token) bool {
    return token != null and token.?.type == .doctype;
}

fn isStartTag(token: ?Token) bool {
    return token != null and token.?.type == .start_tag;
}

fn isEndTag(token: ?Token) bool {
    return token != null and token.?.type == .end_tag;
}

fn isStartOrEndTagWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    if (!isStartTag(token) and !isEndTag(token)) return false;

    for (names) |name| {
        if (std.mem.eql(u8, switch (token.?.type) {
            .start_tag => |t| t.name,
            .end_tag => |t| t.name,
            else => unreachable,
        }.slice(source), name)) return true;
    }

    return false;
}

fn isStartOrEndTagNotWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    if (!isStartTag(token) and !isEndTag(token)) return false;

    for (names) |name| {
        if (std.mem.eql(u8, switch (token.?.type) {
            .start_tag => |t| t.name,
            .end_tag => |t| t.name,
            else => unreachable,
        }.slice(source), name)) return false;
    }

    return true;
}

fn isStartTagWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    return isStartTag(token) and isStartOrEndTagWithName(token, source, names);
}

fn isEndTagWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    return isEndTag(token) and isStartOrEndTagWithName(token, source, names);
}

fn isStartTagNotWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    return isStartTag(token) and isStartOrEndTagNotWithName(token, source, names);
}

fn isEndTagNotWithName(token: ?Token, source: []const u8, names: []const []const u8) bool {
    return isEndTag(token) and isStartOrEndTagNotWithName(token, source, names);
}

pub fn dispatch(tree_constructor: *TreeConstructor, tokenizer: *Tokenizer, source: []const u8, token: ?Token) !void {
    // TODO: Foreign content

    if (token != null and token.?.type == .character and
        token.?.type.character.slice(source).len > std.unicode.utf8ByteSequenceLength(token.?.type.character.slice(source)[0]) catch @panic("TODO"))
    {
        var rem = token.?.type.character;
        while (rem.slice(source).len > 0) {
            const sequence_len = std.unicode.utf8ByteSequenceLength(rem.slice(source)[0]) catch @panic("TODO");
            std.debug.assert(rem.slice(source).len >= sequence_len);
            try tree_constructor.dispatch(tokenizer, source, .{ .type = .{ .character = .{ .start = rem.start, .end = rem.start + sequence_len } } });
            rem.start += sequence_len;
        }
    } else {
        mode: switch (tree_constructor.insertion_mode) {
            .initial => {
                if (isWhitespaceCharacterToken(token, source)) {
                    // Ignore token
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    if (token.?.type.doctype.name == null or !std.mem.eql(u8, token.?.type.doctype.name.?.slice(source), "html") or
                        token.?.type.doctype.public != null or
                        (token.?.type.doctype.system != null and !std.mem.eql(u8, token.?.type.doctype.system.?.slice(source), "about:legacy-compat")))
                    {
                        @panic("TODO");
                    }

                    const doctype = try tree_constructor.dom.createDocumentType((token.?.type.doctype.name orelse Token.Span.empty).slice(source));
                    if (token.?.type.doctype.public) |public| tree_constructor.dom.getDocumentType(doctype).?.public_id = public.slice(source);
                    if (token.?.type.doctype.system) |system| tree_constructor.dom.getDocumentType(doctype).?.system_id = system.slice(source);
                    try tree_constructor.dom.appendToDocument(tree_constructor.document_id, .{ .document_type = doctype });

                    // TODO: Quirks mode (and limited quirks mode) checks

                    tree_constructor.insertion_mode = .before_html;
                } else {
                    @panic("TODO");
                }
            },
            .before_html => {
                if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isWhitespaceCharacterToken(token, source)) {
                    // Ignore token
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    const element = try tree_constructor.createElementForToken(source, token);
                    try tree_constructor.dom.appendToDocument(tree_constructor.document_id, .{ .element = element });
                    try tree_constructor.open_elements.append(tree_constructor.allocator, element);

                    tree_constructor.insertion_mode = .before_head;
                } else if (isEndTagNotWithName(token, source, &.{ "head", "body", "html", "br" })) {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .before_head => {
                if (isWhitespaceCharacterToken(token, source)) {
                    // Ignore token
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"head"})) {
                    const element = try tree_constructor.insertElementForToken(source, token);
                    tree_constructor.head = element;
                    tree_constructor.insertion_mode = .in_head;
                } else if (isEndTagNotWithName(token, source, &.{ "head", "body", "html", "br" })) {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .in_head => {
                if (isWhitespaceCharacterToken(token, source)) {
                    try tree_constructor.insertCharacter(token.?.type.character.slice(source));
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "base", "basefont", "bgsound", "link" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"meta"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"title"})) {
                    @panic("TODO");
                } else if ((isStartTagWithName(token, source, &.{"noscript"}) and tree_constructor.scripting_enabled) or
                    isStartTagWithName(token, source, &.{ "noframes", "style" }))
                {
                    _ = try tree_constructor.insertElementForToken(source, token);

                    tokenizer.state = .rawtext;
                    tree_constructor.original_insertion_mode = tree_constructor.insertion_mode;
                    tree_constructor.insertion_mode = .text;
                } else if (isStartTagWithName(token, source, &.{"noscript"}) and !tree_constructor.scripting_enabled) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"script"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"head"})) {
                    const head_element = tree_constructor.open_elements.pop().?;
                    std.debug.assert(std.mem.eql(u8, tree_constructor.dom.getElement(head_element).?.tag_name, "head"));

                    tree_constructor.insertion_mode = .after_head;
                } else if (isEndTagWithName(token, source, &.{ "body", "html", "br" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"template"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"template"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"head"}) or isEndTag(token)) {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .in_head_noscript => @panic("TODO"),
            .after_head => {
                if (isWhitespaceCharacterToken(token, source)) {
                    try tree_constructor.insertCharacter(token.?.type.character.slice(source));
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"body"})) {
                    _ = try tree_constructor.insertElementForToken(source, token);
                    tree_constructor.frameset_ok = false;
                    tree_constructor.insertion_mode = .in_body;
                } else if (isStartTagWithName(token, source, &.{"frameset"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title" })) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"template"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"head"}) or
                    isEndTagNotWithName(token, source, &.{ "body", "html", "br" }))
                {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .in_body => {
                if (isNullCharacterToken(token, source)) {
                    @panic("TODO");
                } else if (isWhitespaceCharacterToken(token, source)) {
                    tree_constructor.reconstructActiveFormattingElements();
                    try tree_constructor.insertCharacter(token.?.type.character.slice(source));
                } else if (isCharacterToken(token)) {
                    tree_constructor.reconstructActiveFormattingElements();
                    try tree_constructor.insertCharacter(token.?.type.character.slice(source));
                    tree_constructor.frameset_ok = false;
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title" }) or
                    isEndTagWithName(token, source, &.{"template"}))
                {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"body"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"frameset"})) {
                    @panic("TODO");
                } else if (isEof(token)) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"body"})) {
                    if (!tree_constructor.hasElementInScope("body")) {
                        @panic("TODO");
                    } else {
                        for (tree_constructor.open_elements.items) |element| {
                            var match = false;
                            inline for (&.{ "dd", "dt", "li", "optgroup", "option", "p", "rb", "rp", "rt", "rtc", "tbody", "td", "tfoot", "th", "thead", "tr", "body", "html" }) |name| {
                                if (std.mem.eql(u8, tree_constructor.dom.getElement(element).?.tag_name, name)) {
                                    match = true;
                                }
                            }

                            if (!match) {
                                @panic("TODO");
                            }
                        }

                        tree_constructor.insertion_mode = .after_body;
                    }
                } else if (isEndTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav", "ol", "p", "search", "section", "summary", "ul" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "h1", "h2", "h3", "h4", "h5", "h6" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "pre", "listing" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"form"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"li"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "dd", "dt" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"plaintext"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"button"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{ "address", "article", "aside", "blockquote", "button", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search", "section", "select", "summary", "ul" })) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"form"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"p"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"li"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{ "dd", "dt" })) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{ "h1", "h2", "h3", "h4", "h5", "h6" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"a"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"nobr"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{ "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "applet", "marquee", "object" })) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{ "applet", "marquee", "object" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"table"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"br"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "area", "br", "embed", "img", "keygen", "wbr" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"input"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "param", "source", "track" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"hr"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"image"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"textarea"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"xmp"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"iframe"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"noembed"}) or
                    (isStartTagWithName(token, source, &.{"noscript"}) and tree_constructor.scripting_enabled))
                {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"select"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"option"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"optgroup"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"option"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "rb", "rtc" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "rp", "rt" })) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"math"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"svg"})) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{ "caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr" })) {
                    @panic("TODO");
                } else if (isStartTag(token)) {
                    tree_constructor.reconstructActiveFormattingElements();
                    _ = try tree_constructor.insertElementForToken(source, token);
                } else if (isEndTag(token)) blk: {
                    var i: usize = 0;
                    var node = tree_constructor.open_elements.items[tree_constructor.open_elements.items.len - 1 - i];
                    while (true) {
                        if (std.mem.eql(u8, tree_constructor.dom.getElement(node).?.tag_name, token.?.type.end_tag.name.slice(source))) {
                            tree_constructor.generateImpliedEndTagsExcept(token.?.type.end_tag.name.slice(source));

                            if (node != tree_constructor.currentElement()) {
                                @panic("TODO");
                            }

                            while (node != tree_constructor.currentElement().?) {
                                _ = tree_constructor.open_elements.pop().?;
                            }
                            _ = tree_constructor.open_elements.pop().?;
                            break :blk;
                        } else if (isSpecialCategoryTagName(tree_constructor.dom.getElement(node).?.tag_name)) {
                            @panic("TODO");
                        }
                        i += 1;
                        node = tree_constructor.open_elements.items[tree_constructor.open_elements.items.len - 1 - i];
                    }
                } else unreachable;
            },
            .text => {
                if (isCharacterToken(token)) {
                    try tree_constructor.insertCharacter(token.?.type.character.slice(source));
                } else if (isEof(token)) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"script"})) {
                    @panic("TODO");
                } else if (isEndTag(token)) {
                    _ = tree_constructor.open_elements.pop().?;
                    tree_constructor.insertion_mode = tree_constructor.original_insertion_mode.?;
                    tree_constructor.original_insertion_mode = null;
                } else unreachable;
            },
            .in_table => @panic("TODO"),
            .in_table_text => @panic("TODO"),
            .in_caption => @panic("TODO"),
            .in_column_group => @panic("TODO"),
            .in_table_body => @panic("TODO"),
            .in_row => @panic("TODO"),
            .in_cell => @panic("TODO"),
            .in_template => @panic("TODO"),
            .after_body => {
                if (isWhitespaceCharacterToken(token, source)) {
                    continue :mode .in_body;
                } else if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token)) {
                    @panic("TODO");
                } else if (isStartTagWithName(token, source, &.{"html"})) {
                    @panic("TODO");
                } else if (isEndTagWithName(token, source, &.{"html"})) {
                    // TODO: Fragment parser handler

                    tree_constructor.insertion_mode = .after_after_body;
                } else if (isEof(token)) {
                    @panic("TODO");
                } else {
                    @panic("TODO");
                }
            },
            .in_frameset => @panic("TODO"),
            .after_frameset => @panic("TODO"),
            .after_after_body => {
                if (isCommentToken(token)) {
                    @panic("TODO");
                } else if (isDoctypeToken(token) or
                    isWhitespaceCharacterToken(token, source) or
                    isStartTagWithName(token, source, &.{"html"}))
                {
                    continue :mode .in_body;
                } else if (isEof(token)) {
                    // Done
                } else {
                    @panic("TODO");
                }
            },
            .after_after_frameset => @panic("TODO"),
        }
    }
}
