const std = @import("std");
const Allocator = std.mem.Allocator;

const Cfp = @import("cfp").Cfp;

pub fn main() !void {
    std.debug.print("Code coverage examples!\n", .{});

    // Let's start from here...

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    const path = try getUri(heap, "app.conf");
    defer heap.free(path);

    try Cfp.init(heap, .{.abs_path = path});
    defer Cfp.deinit();

    // Extracts integer into the given integer type
    std.debug.assert(try Cfp.getInt(u8, "global.prop_1") == 100);
    std.debug.assert(try Cfp.getInt(u32, "global.prop_1") == 100);
    std.debug.assert(try Cfp.getInt(isize, "global.prop_1") == 100);
    std.debug.assert(try Cfp.getInt(usize, "global.prop_1") == 100);

    // Extracts boolean value
    std.debug.assert(try Cfp.getBool("global.prop_2") == true);

    // Extracts string slice
    const data = try Cfp.getStr("global.prop_3");
    std.debug.assert(std.mem.eql(u8, "hello", data));

    // Extracts List Values
    const items = try Cfp.getList("global.prop_4");
    std.debug.assert(items[0].number == 100);
    std.debug.assert(items[1].boolean == true);
    std.debug.assert(std.mem.eql(u8, "hello", items[2].string));

    // Extracts string slice from a nested section
    const data2 = try Cfp.getStr("project.one.one.prop");
    std.debug.assert(std.mem.eql(u8, "hello", data2));

    // Extracts List Values
    const nested_items = try Cfp.getList("project.two.prop");
    std.debug.assert(nested_items[0].number == 100);
    std.debug.assert(nested_items[1].boolean == true);
    std.debug.assert(std.mem.eql(u8, "hello", nested_items[2].string));

    std.debug.print("Well done!\n", .{});
}

/// **Remarks:** Return value must be freed by the caller.
fn getUri(heap: Allocator, child: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(heap);
    defer heap.free(exe_dir);

    if (std.mem.count(u8, exe_dir, "zig-out/bin") == 1) {
        const fmt_str = "{s}/../../{s}";
        return try std.fmt.allocPrint(heap, fmt_str, .{exe_dir, child});
    }

    unreachable;
}