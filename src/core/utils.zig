//! Utility Module

const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;

const Str = []const u8;

/// # Loads File Content
/// **WARNING:** Return value must be freed by the caller
/// - `dir` - Absolute directory path. When **null**, `cwd()` is used
/// - `path` - A sub file path relative to the given `dir` or `cwd()`
/// - `max_size` - Maximum file size in bytes for the IO buffered reader
pub fn loadFile(heap: Allocator, dir: ?Str, path: Str, max_size: usize) !Str {
    var file: fs.File = undefined;
    defer file.close();

    if (dir) |d| {
        var abs_dir = try std.fs.openDirAbsolute(d, .{});
        file = try abs_dir.openFile(path, .{});
        abs_dir.close();
    } else {
        file = try std.fs.cwd().openFile(path, .{});
    }

    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();

    return try input_stream.readAllAlloc(heap, max_size);
}
