const std = @import("std");

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

    // When you are running: ./zig-out/bin/cfp.exe
    // Make sure to change this path to `{s}/../../app.conf`
    const path = try std.fmt.allocPrint(heap, "{s}/../../../app.conf", .{dir});
    defer heap.free(path);

    try Cfp.init(heap, .{.abs_path = path});
    defer Cfp.deinit();

    // Let's start from here...
    
}
