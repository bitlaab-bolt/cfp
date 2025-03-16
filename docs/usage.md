# How to use

First import Cfp on your zig file.

```zig
const cfp = @import("cfp");
const Cfp = cfp.Cfp;
```

Create an `app.conf` file on your projects root directory, then copy and paste the following code into it.

```conf
# Flat section

global {
    prop_1 = 100
    prop_2 = true
    prop_3 = "hello"
    prop_4 = [100, true, "hello"]
}

# Nested sections

project {
    one { one { prop = "hello" } }
    two {
        prop = [100, true, "hello"]
        foo = "bar"
    }
}

applet {
    proj_1 {
        host_name = "example.com"
        shared_object = "../proj-1/zig-out/lib/lib-proj-1.so"
    }
}
```

## Syntax and Definitions

The above configuration snippet highlights a barebones config structure along with all supported node and data types.

**Node Types**

- `comment` - single line comment ending with `\n`
- `section` - contains arbitrary number of nested sections or properties
- `property` - contains arbitrary number of `<key> = <value> | <value list>`

**Remarks:** `property` can only be used within a section. Any top level property will cause the parser to fail with the **InvalidFormat** error.

**Data Types**

- `string` - value of `Str`
- `boolean` - value of `true | false`
- `number` - a signed integer of `isize`
- `list` - any number of `,` separated `[<value 1>,...<value N>]`

**Remarks** `list` can contain any combination of above scaler types.

**Flat vs Nested Section**

A section with only property nodes is called a flat section, on the other hand a section with only section nodes is called a nested section.

## Limitation

As of now, a section with mixed sections as below will result to a recursive panic with segmentation fault.

```conf title="app.conf"
settings {
    prop_1 = 100
    prop_2 {
        prop_3 = "hello"
    }
}
```

## Code Example

The following code example demonstrates how to access configuration data at runtime. Cfp uses `.` notation to access nested sections and properties at any level.

```zig
var gpa_mem = std.heap.DebugAllocator(.{}){};
defer std.debug.assert(gpa_mem.deinit() == .ok);
const heap = gpa_mem.allocator();

try Cfp.init(heap, .{.path = "app.conf"});
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
```

For dynamic and runtime known configuration make sure to checkout `Cfp.getProperties()` and `Cfp.getSections()` at [API Reference](/reference).
