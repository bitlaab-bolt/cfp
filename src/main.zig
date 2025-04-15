const std = @import("std");
const Allocator = std.mem.Allocator;

const cfp = @import("cfp");
const Cfp = cfp.Cfp;

pub fn main() !void {
    var gpa_mem = std.heap.DebugAllocator(.{}).init;
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    std.debug.print("Hello, World!\n", .{});

    const dir = try std.fs.selfExeDirPathAlloc(heap);
    defer heap.free(dir);

    // Create a demo `app.conf` file 

    const path = try getUri(heap, "app.conf");
    defer heap.free(path);

    try Cfp.init(heap, .{.abs_path = path});
    defer Cfp.deinit();

    // Let's start from here...
    
}

/// **Remarks:** Return value must be freed by the caller.
fn getUri(heap: Allocator, child: []const u8) ![]const u8 {
    const exe_dir = try std.fs.selfExeDirPathAlloc(heap);
    defer heap.free(exe_dir);

    if (std.mem.count(u8, exe_dir, ".zig-cache") == 1) {
        const fmt_str = "{s}/../../../{s}";
        return try std.fmt.allocPrint(heap, fmt_str, .{exe_dir, child});
    } else if (std.mem.count(u8, exe_dir, "zig-out") == 1) {
        const fmt_str = "{s}/../../{s}";
        return try std.fmt.allocPrint(heap, fmt_str, .{exe_dir, child});
    } else {
        unreachable;
    }
}