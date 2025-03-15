const std = @import("std");

const cfp = @import("cfp");
const Cfp = cfp.Cfp;

pub fn main() !void {
    var gpa_mem = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(gpa_mem.deinit() == .ok);
    const heap = gpa_mem.allocator();

    std.debug.print("Hello, World!\n", .{});

    try Cfp.init(heap, "app.conf");
    defer Cfp.deinit();

    // Let's start from here...
    
}
