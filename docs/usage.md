# How to use

Cfp parses a custom `.conf` file into an in-memory tree and exposes it through a
process-wide singleton. Configuration is read with typed getters that use `.`
notation to address any section or property at any depth.

First, import Cfp on your Zig source file.

```zig
const Cfp = @import("cfp").Cfp;
```

## The configuration file

Create an `app.conf` file in your project's root directory. The following
snippet demonstrates every supported node and data type.

```conf title="app.conf"
# Flat section: contains only properties
global {
    name = "cfp-demo"
    port = 8080                        # inline comments work after bare values
    verbose = true
    build_number = -7                  # numbers are signed (`isize`)
    tags = ["core", "net", 42, true]   # lists may mix every scalar type
}

# Nested section: sections containing other sections only
project {
    web {
        host_name = "example.com"
        shared_object = "../proj-1/zig-out/lib/lib-proj-1.so"
    }

    workers {
        count = 8
        names = ["alice", "bob", "carol"]
    }
}

# Runtime-known sections, enumerated with Cfp.getSections()
applet {
    proj_1 {
        host_name = "example.com"
        shared_object = "../proj-1/zig-out/lib/lib-proj-1.so"
    }
}
```

### Syntax and Definitions

**Node Types**

- `comment` - starts with `#` and ends at the newline; allowed on its own line or after a value
- `section` - contains an arbitrary number of nested sections or properties
- `property` - contains an arbitrary number of `<key> = <value>` or `<key> = <value list>` lines

**Remarks:** `property` can only be used within a section. Any top level
property will cause the parser to fail with the **InvalidFormat** error.

**Data Types**

- `string` - value of `Str` (quoted)
- `boolean` - value of `true | false`
- `number` - a signed integer of `isize`
- `list` - any number of `,` separated values `[<value 1>,...<value N>]`

**Remarks:** `list` can contain any combination of the above scalar types.

**Flat vs Nested Section**

A section containing only properties is a *flat* section; a section containing
only sections is a *nested* section. Sections never mix the two.

```conf
settings {
    prop_1 = 100        # flat part ...
    props {             # ... followed by a nested section: InvalidFormat!
        prop_2 = "oops"
    }
}
```

**Limitations**

- A section may not mix properties and sections; the parser fails with
  **InvalidFormat**.
- Keywords may only contain alphanumerics and `_`; anything else fails with
  **InvalidKeyword**.
- Inline comments are supported after bare values; a `#` inside a quoted
  string is fine, but not inside a list token.

## Initialize the singleton

Copy the following helper into your `main.zig`; it resolves `app.conf`
relative to the executable so that `zig build run` works out of the box.

```zig
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
```

`init` takes an optional environment identifier (stored as a raw `u8`) and the
absolute config path. Calling `init` twice without `deinit` in between panics.

```zig
const Env = enum(u8) { dev = 1, stage = 2, prod = 3 };

try Cfp.init(init.io, init.gpa, .{
    .env = @intFromEnum(Env.dev),
    .abs_path = path,
});
defer Cfp.deinit();
```

**Remarks:** After `Cfp.deinit()` all slices previously returned by the getters
are invalid. A fresh `Cfp.init()` is allowed afterwards.

## Read values

Queries use `.` notation for any nesting depth, e.g. `project.web.host_name`.
Every getter returns an error union; wrong types and unknown paths are
reported as errors instead of panicking.

```zig
// Integers convert into any integer type
const port = try Cfp.getInt(u16, "global.port");        // 8080
const build = try Cfp.getInt(isize, "global.build_number"); // -7

// Booleans and strings
const verbose = try Cfp.getBool("global.verbose");
const name = try Cfp.getStr("global.name");

// Lists may mix scalar types; switch on each `Value`
const tags = try Cfp.getList("global.tags");
for (tags, 0..) |value, i| {
    switch (value) {
        .number => |n| std.debug.print("{d}\n", .{n}),
        .boolean => |b| std.debug.print("{}\n", .{b}),
        .string => |s| std.debug.print("{s}\n", .{s}),
    }
}

// Dot notation reaches any depth
const host = try Cfp.getStr("project.web.host_name");
```

## Runtime-known data

When section or property names are only known at runtime, use
`getSections()` and `getProperties()`:

- `Cfp.getSections(query)` - returns the child sections of the given path
- `Cfp.getProperties(query)` - returns the properties of the addressed
  (flat) section

Both accept the same `.` queries as the typed getters and return `null` when
the path does not resolve.

```zig
// Enumerate sections and query each one dynamically
if (Cfp.getSections("applet")) |applets| {
    for (applets) |app| {
        const query = try std.fmt.allocPrint(
            heap, "applet.{s}.host_name", .{app.name}
        );
        defer heap.free(query);

        std.debug.print("{s} -> {s}\n", .{app.name, try Cfp.getStr(query)});
    }
}
```

## Error handling

All getters return Zig errors, so failures compose with ordinary `try` and
`catch`. The error set is inferred; match on the names below via
`@errorName(err)`.

| Error                | Raised when                                            |
| -------------------- | ------------------------------------------------------ |
| `InvalidQuery`       | The query path does not resolve to a property          |
| `UnexpectedDataType` | The stored type differs, or an integer does not fit `T` |
| `InvalidFormat`      | Structural problem (top level property, missing `}`)   |
| `UnexpectedEOF`      | The file ends mid-token or an unclosed section          |
| `InvalidToken`       | A value token is malformed (e.g. `trueX`, empty list slot) |
| `InvalidKeyword`     | A section/property name has illegal characters         |

Parse failures are logged with the offending `line:column` and a source trace,
then returned to the caller:

```zig
try Cfp.init(init.io, heap, .{.abs_path = path}); // or `catch` and recover
```
