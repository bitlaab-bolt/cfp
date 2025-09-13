const std = @import("std");
const Allocator = std.mem.Allocator;

const Cfp = @import("cfp").Cfp;

pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});

    // Let's start from here...

    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    const path = try getUri(heap, "app.conf");
    defer heap.free(path);

    try Cfp.init(heap, .{.abs_path = path});
    defer Cfp.deinit();
}

fn getUri(heap: Allocator, child: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(heap);
    defer heap.free(exe_dir);

    if (std.mem.count(u8, exe_dir, "zig-out/bin") == 1) {
        const fmt_str = "{s}/../../{s}";
        return try std.fmt.allocPrint(heap, fmt_str, .{exe_dir, child});
    }

    unreachable;
}