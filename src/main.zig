const std = @import("std");
const Allocator = std.mem.Allocator;

const Cfp = @import("cfp").Cfp;

/// # Environment identifier passed to `Cfp.init()` via `Option.env`.
const Env = enum(u8) { dev = 1, stage = 2, prod = 3 };


pub fn main(init: std.process.Init) !void {
    const heap = init.gpa;

    // Resolve `app.conf` relative to the executable
    const path = try getUri(heap, init.io, "app.conf");
    defer heap.free(path);

    try Cfp.init(init.io, heap, .{
        .env = @intFromEnum(Env.dev),
        .abs_path = path,
    });
    defer Cfp.deinit();

    std.debug.print(
        "<== Running in `{s}` environment ==>\n\n",
        .{@tagName(Cfp.getEnv(Env).?)}
    );

    // # Typed Property Access
    // - Every getter returns `!T`; queries use `.` notation at any depth
    const name = try Cfp.getStr("global.name");
    const port = try Cfp.getInt(u16, "global.port");
    const verbose = try Cfp.getBool("global.verbose");
    const build = try Cfp.getInt(isize, "global.build_number");

    std.debug.print("name    : {s}\n", .{name});
    std.debug.print("port    : {d}\n", .{port});
    std.debug.print("verbose : {}\n", .{verbose});
    std.debug.print("build   : {d}\n", .{build});

    // # Out-Of-Range
    // - Conversions are ordinary errors (not crashes)
    if (Cfp.getInt(u8, "global.port")) |too_small| {
        std.debug.print("port as u8: {d}\n", .{too_small});
    } else |err| {
        std.debug.print(
            "error.{s} (8080 does not fit into u8)\n",
            .{@errorName(err)}
        );
    }

    // # Mixed Lists
    // - Switch on each `Value` to handle every variant
    // - A list may hold any combination of numbers, booleans and strings
    const tags = try Cfp.getList("global.tags");

    std.debug.print("tags    : [", .{});
    for (tags, 0..) |value, i| {
        if (i != 0) std.debug.print(", ", .{});
        switch (value) {
            .number => |n| std.debug.print("{d}", .{n}),
            .boolean => |b| std.debug.print("{}", .{b}),
            .string => |s| std.debug.print("\"{s}\"", .{s}),
        }
    }
    std.debug.print("]\n\n", .{});

    // # Nested Queries
    // - Dot notation reaches any nesting level
    // - A query segment can point at a property of any type
    std.debug.print(
        "host    : {s}\n",
        .{try Cfp.getStr("project.web.host_name")}
    );
    std.debug.print(
        "workers : {d}\n",
        .{try Cfp.getInt(u8, "project.workers.count")}
    );

    for (try Cfp.getList("project.workers.names")) |worker| {
        std.debug.print("  worker: {s}\n", .{worker.string});
    }

    // # Runtime-Known Data
    // - Sections and properties that are only known at runtime are enumerated
    //   with `getSections()` / `getProperties()`.
    std.debug.print("\napplets (enumerated at runtime):\n", .{});

    if (Cfp.getSections("applet")) |applets| {
        for (applets) |app| {
            // Query paths can also be composed at runtime
            const query = try std.fmt.allocPrint(
                heap, "applet.{s}.host_name", .{app.name}
            );
            defer heap.free(query);

            std.debug.print("  {s:<8} -> {s}\n", .{app.name, try Cfp.getStr(query)});
        }
    }

    std.debug.print(
        "\nflat section `global`, dumped via `getProperties()`:\n", .{}
    );

    if (Cfp.getProperties("global")) |items| dumpItems("global", items);

    std.debug.print("\nfull `project` tree via `getSections()`:\n", .{});

    if (Cfp.getSections("project")) |secs| dumpSections("project", secs);

    // # Error Handling
    // - Errors are plain Zig errors: catch them, wrap them, or propagate them.
    std.debug.print("\nerror handling:\n", .{});

    if (Cfp.getStr("does.not.exist")) |value| {
        std.debug.print("  {s}\n", .{value});
    } else |err| {
        std.debug.print(
            "  getStr(\"does.not.exist\")    -> error.{s}\n",
            .{@errorName(err)}
        );
    }

    if (Cfp.getValue("global.port")) |value| {
        std.debug.print(
            "  global.port is `{s}`, not a string\n",
            .{@tagName(value)}
        );
    } else |err| {
        std.debug.print(
            "  getValue(\"global.port\") -> error.{s}\n",
            .{@errorName(err)}
        );
    }

    std.debug.print("\nWell done!\n", .{});
}

/// - Recursively prints every value of a flat section together with its
///   `.`-separated query path. Queries are composed at runtime, which is why
///   `anytype` is used for the (private) Cfp item types.
fn dumpItems(prefix: []const u8, items: anytype) void {
    for (items) |item| {
        switch (item) {
            .pair => |pair| switch (pair.value) {
                .number => |n| std.debug.print(
                    "  {s}.{s} = {d}\n", .{prefix, pair.name, n}
                ),
                .boolean => |b| std.debug.print(
                    "  {s}.{s} = {}\n", .{prefix, pair.name, b}
                ),
                .string => |s| std.debug.print(
                    "  {s}.{s} = \"{s}\"\n", .{prefix, pair.name, s}
                )
            },
            .list => |list| {
                std.debug.print("  {s}.{s} = [", .{prefix, list.name});
                for (list.values, 0..) |value, i| {
                    if (i != 0) std.debug.print(", ", .{});
                    switch (value) {
                        .number => |n| std.debug.print("{d}", .{n}),
                        .boolean => |b| std.debug.print("{}", .{b}),
                        .string => |s| std.debug.print("\"{s}\"", .{s}),
                    }
                }
                std.debug.print("]\n", .{});
            }
        }
    }
}

/// - Recursively prints every section under `parent` using `.` query paths.
fn dumpSections(parent: []const u8, secs: anytype) void {
    for (secs) |sec| {
        var buf: [128]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "{s}.{s}", .{parent, sec.name}) catch return;

        switch (sec.data) {
            .flat => |items| dumpItems(path, items),
            .nested => |children| dumpSections(path, children),
        }
    }
}

/// **WARNING:** Return value must be freed by the caller.
fn getUri(heap: Allocator, io: std.Io, child: []const u8) ![]const u8 {
    const exe_dir = try std.process.executableDirPathAlloc(io, heap);
    defer heap.free(exe_dir);

    if (std.mem.count(u8, exe_dir, "zig-out/bin") == 1) {
        const fmt_str = "{s}/../../{s}";
        return try std.fmt.allocPrint(heap, fmt_str, .{exe_dir, child});
    }

    unreachable;
}
