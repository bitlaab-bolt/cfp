//! Utility Module

const std = @import("std");
const Allocator = std.mem.Allocator;

const Str = []const u8;

/// # Loads File Content
/// **WARNING:** Return value must be freed by the caller
/// - `max_size` - Maximum file size in bytes for the IO buffered reader
pub fn loadFile(heap: Allocator, path: Str, max_size: usize) !Str {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();

    return try input_stream.readAllAlloc(heap, max_size);
}
