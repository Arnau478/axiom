const std = @import("std");

pub fn fetch(url: []const u8, about: std.StaticStringMap([]const u8)) ![]const u8 {
    const parsed = try std.Uri.parse(url);
    if (std.mem.eql(u8, parsed.scheme, "about")) {
        return about.get(parsed.path.percent_encoded).?;
    } else {
        @panic("TODO");
    }
}
