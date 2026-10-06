//! # Utility Module

const std = @import("std");
const Io = std.Io;
const fs = std.fs;
const mem = std.mem;
const debug = std.debug;
const Allocator = std.mem.Allocator;
const SrcLoc = std.builtin.SourceLocation;


const Str = []const u8;

/// # Loads File Content
/// - `path` - An absolute file path (e.g., `/users/john/demo.txt`).
///
/// **WARNING:** Return value must be freed by the caller.
pub fn loadFile(io: Io, heap: Allocator, path: Str) !Str {
    return loadFileZ(io, heap, path) catch |err| {
        const fmt_str = "File system error on: {s}";
        log(.err, fmt_str, .{path}, @src());
        return err;
    };
}

fn loadFileZ(io: Io, heap: Allocator, path: Str) !Str {
    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const file_sz = try file.length(io);
    const contents = try heap.alloc(u8, file_sz);
    debug.assert(try file.readPositionalAll(io, contents, 0) == file_sz);
    return contents;
}

const Log = enum { info, warn, err };

/// # Synchronous Terminal Logger
/// A wrapper around `std.log` with additional source information
pub fn log(kind: Log, comptime format: Str, args: anytype, src: SrcLoc) void {
    switch (kind) {
        .info => std.log.info(format, args),
        .warn => std.log.warn(format, args),
        .err => std.log.err(format, args)
    }
    const fmt_str = "source: {s} at {d}:{d}\n";
    debug.print(fmt_str, .{src.file, src.line, src.column});
}
