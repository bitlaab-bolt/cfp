//! # Configuration File Parser
//! - Parses custom `.conf` file from the given file path
//! - Creates a singleton instance to be used across the codebase
//! - Extracts configuration file data into `Cfp` structure at runtime
//!
//! ## Syntax and Definitions
//!
//! **Node Types**
//! - `comment` - single line comment ending with `\n`
//! - `section` - contains arbitrary number of nested sections or properties
//! - `property` - contains arbitrary number of `<key> = <value> | <value list>`
//!
//! **Data Types**
//! - `string` - value of `Str`
//! - `boolean` - value of `true | false`
//! - `number` - a signed integer of `isize`
//! - `list` - any number of `,` separated `[<value 1>,...<value N>]`
//!
//! **Remarks:** `list` can contain any combination of above scaler types.
//!
//! See `test` code at the end for writing custom configurations for a new app.

const std = @import("std");
const mem = std.mem;
const ascii = std.ascii;
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;

const utils = @import("./utils.zig");
const Parser = @import("./parser.zig");


const Str = []const u8;

const Error = error {
    InvalidQuery,
    InvalidToken,
    InvalidFormat,
    UnexpectedEOF,
    InvalidKeyword,
    UnexpectedDataType,
};

const SingletonObject = struct {
    heap: Allocator,
    env: ?u8,
    src: Str,
    secs: []Section,
};

var so: ?SingletonObject = null;

const Self = @This();

pub const Option = struct { env: ?u8 = null, abs_path: Str };

/// # Initializes a Singleton
/// - `opt.env` - An optional environment identifier `Dev`, `Prod` etc.
/// - `opt.abs_path` - An absolute app configuration file path
pub fn init(heap: Allocator, opt: Option) !void {
    if (Self.so != null) @panic("Initialize Only Once Per Process!");

    const max_size = 1024 * 1024 * 1; // 1 MB
    const src_data = try utils.loadFile(heap, opt.abs_path, max_size);

    var p = Parser.init(src_data);
    const data = SourceContent.parse(heap, &p) catch |err| {
        const info = p.info();
        const trace = p.trace(256);
        std.log.err(
            "{s} at line {d}:{d}\n\n{s} <<< HERE\n",
            .{opt.abs_path, info.line, info.column, trace}
        );

        heap.free(src_data);
        return err;
    };

    Self.so = .{.heap = heap, .env = opt.env, .src = src_data, .secs = data};
}

/// # Destroys the Singleton
pub fn deinit() void {
    const sop = Self.iso();

    for (sop.secs) |*sec| free(sop.heap, sec);

    sop.heap.free(sop.secs);
    sop.heap.free(sop.src);
}

/// # Internal Static Object
fn iso() *SingletonObject {
    if (Self.so == null) @panic("Singleton is not Initialized");
    return &Self.so.?;
}

fn free(heap: Allocator, section: *Section) void {
    switch (section.data) {
        .flat => |items| {
            for (items) |item| {
                if (item == .list) heap.free(item.list.values);
            }
            heap.free(items);
        },
        .nested => |sections| {
            for (sections) |*data| free(heap, data);
            heap.free(sections);
        }
    }
}

/// # Returns the Environment Value
/// **Remarks:** If env is not set at `init()`, **null** will be returned.
/// - `T` - Must be an user defined enum type.
pub fn getEnv(comptime T: type) ?T {
    if (@typeInfo(T) != .@"enum") {
        const err_str = "cfp: `T` Must be an Enum Type. Found `{s}`";
        @compileError(std.fmt.comptimePrint(err_str, .{@typeName(T)}));
    }

    const sop = Self.iso();
    return if (sop.env) |env| @as(T, @enumFromInt(env)) else null;
}

/// # Returns an Integer Value
/// - `T` - Must be a valid integer type e.g., `u8`, `i32`, `usize` etc.
pub fn getInt(comptime T: type, query: Str) !T {
    if (@typeInfo(T) != .int) {
        const err_str = "cfp: `T` Must be an Integer Type. Found `{s}`";
        @compileError(std.fmt.comptimePrint(err_str, .{@typeName(T)}));
    }

    const v = try getValue(query);
    return if (@as(Value, v) == Value.number) @as(T, @intCast(v.number))
    else Error.UnexpectedDataType;
}

/// # Returns a Boolean Value
pub fn getBool(query: Str) !bool {
    const v = try getValue(query);
    return if (@as(Value, v) == Value.boolean) v.boolean
    else Error.UnexpectedDataType;
}

/// # Returns a String Slice
pub fn getStr(query: Str) !Str {
    const v = try getValue(query);
    return if (@as(Value, v) == Value.string) v.string
    else Error.UnexpectedDataType;
}

/// # Extracts Pair Value
pub fn getValue(query: Str) !Value {
    const offset = tailIndex(query);
    if (getProperties(query[0..offset])) |items| {
        for(items) |item| {
            if (@as(Item, item) == Item.pair
                and mem.eql(u8, item.pair.name, query[offset + 1..]))
            {
                return item.pair.value;
            }
        }
    }
    return Error.InvalidQuery;
}

/// # Extracts List Values
pub fn getList(query: Str) ![]Value {
    const offset = tailIndex(query);
    if (getProperties(query[0..offset])) |items| {
        for(items) |item| {
            if (@as(Item, item) == Item.list
                and mem.eql(u8, item.list.name, query[offset + 1..]))
            {
                return item.list.values;
            }
        }
    }
    return Error.InvalidQuery;
}

/// # Returns the Last Token Offset
fn tailIndex(query: Str) usize {
    var count: usize = 0;
    var keys = mem.tokenizeScalar(u8, query, '.');

    while(keys.next()) |key| {
        if (keys.peek() == null) break;
        count += key.len + 1;
    }

    return count - 1;
}

/// # Extracts Flat Data Items
/// **Remarks:** Use when properties are only known at runtime.
/// e.g., `foo {...}` could have any number of user defined item.
pub fn getProperties(query: Str) ?[]Item {
    const sop = Self.iso();
    var tmp: ?[]Section = null;
    var keys = mem.tokenizeScalar(u8, query, '.');

    while(keys.peek() != null) {
        const key = keys.next().?;
        const parent = tmp orelse sop.secs;
        if (nested(parent, key)) |section| tmp = section
        else {
            if (keys.peek() == null) return flat(parent, key)
            else break;
        }
    }

    return null;
}

/// # Extracts Nested Data Sections
/// **Remarks:** Use when sections are only known at runtime.
/// e.g., `foo {...}` could have any number of user defined section.
pub fn getSections(query: Str) ?[]Section {
    const sop = Self.iso();
    var tmp: ?[]Section = null;
    var keys = mem.tokenizeScalar(u8, query, '.');

    while(keys.peek() != null) {
        const key = keys.next().?;
        const parent = tmp orelse sop.sections;
        if (nested(parent, key)) |section| tmp = section;
    }

    return tmp;
}

fn flat(parent: []Section, name: Str) ?[]Item {
    for (parent) |section| {
        const eql = mem.eql(u8, section.name, name);
        if (eql and @as(Data, section.data) == Data.flat) {
            return section.data.flat;
        }
    }

    return null;
}

fn nested(parent: []Section, name: Str) ?[]Section {
    for (parent) |section| {
        const eql = mem.eql(u8, section.name, name);
        if (eql and @as(Data, section.data) == Data.nested) {
            return section.data.nested;
        }
    }

    return null;
}

//##############################################################################
//# INTERNAL DATA STRUCTURES --------------------------------------------------#
//##############################################################################

const Section = struct { name: Str, data: Data };

const Data = union(enum) { flat: []Item, nested: []Section };

const Item = union(enum) { pair: Pair, list: List };

const Pair = struct { name: Str, value: Value };

const List = struct { name: Str, values: []Value };

const Value = union(enum) { number: isize, boolean: bool, string: Str };

const SourceContent = struct {
    const Keyword = union(enum) { section: Str, property: Str };

    fn parse(heap: Allocator, p: *Parser) ![]Section {
        var sections = ArrayList(Section).init(heap);
        errdefer {
            for (sections.items) |*sec| free(heap, sec);
            sections.deinit();
        }

        try Comments.skip(p); // Skips any top-level comments
        while(p.peek() != null and !p.eat('}')) {
            switch (try keyword(p)) {
                .section => |key| {
                    try sections.append(try SourceContent.nested(heap, p, key));
                },
                .property => return Error.InvalidFormat
            }
        }

        return try sections.toOwnedSlice();
    }

    fn keyword(p: *Parser) !Keyword {
        defer _ = p.eatSp();

        const token = try sanitize(try keywordStr(p));
        const key = try validate(token);
        const tail = try p.peekStr(p.cursor() - 1, p.cursor());

        return if (mem.eql(u8, tail, "=")) Keyword { .property = key }
        else Keyword { .section = key };
    }

    fn keywordStr(p: *Parser) !Str {
        const begin = p.cursor();
        while (!p.eat('{') and !p.eat('=')) { _ = try p.next(); }
        const end = p.cursor() - 1;

        return try p.peekStr(begin, end);
    }

    fn nested(heap: Allocator, p: *Parser, name: Str) !Section {
        var sections = ArrayList(Section).init(heap);
        errdefer {
            for (sections.items) |*sec| free(heap, sec);
            sections.deinit();
        }

        try Comments.skip(p);
        while(p.peek() != null and !p.eat('}')) {
            switch (try keyword(p)) {
                .section => |key| {
                    try sections.append(try SourceContent.nested(heap, p, key));
                },
                .property => |key| {
                    var items = ArrayList(Item).init(heap);
                    try SourceContent.flat(heap, p, &items, key);
                    const data = Data { .flat = try items.toOwnedSlice() };
                    return Section { .name = name, .data = data };
                }
            }
        }

        try Comments.skip(p);
        const data = Data { .nested = try sections.toOwnedSlice() };
        return Section { .name = name, .data = data };
    }

    fn flat(
        heap: Allocator,
        p: *Parser,
        items: *ArrayList(Item),
        name: Str
    ) !void {
        try items.append(try Property.getItem(heap, p, name));
        try Comments.skip(p);

        if (p.eat('}')) { try Comments.skip(p); return; }

        switch (try keyword(p)) {
            .section => return Error.InvalidFormat,
            .property => |key| try SourceContent.flat(heap, p, items, key)
        }
    }
};

const Property = struct {
    fn getItem(heap: Allocator, p: *Parser, key: Str) !Item {
        if (p.peek()) |char| {
            defer _ = p.eatSp();
            switch(char) {
                '[' =>  {
                    _ = try p.next();
                    const token_list = try tokenStr(p, ']');
                    var tokens = mem.tokenizeScalar(u8, token_list, ',');

                    var value_list = ArrayList(Value).init(heap);

                    while(tokens.peek() != null) {
                        const token = tokens.next().?;
                        const data = mem.trim(u8, token, &ascii.whitespace);
                        switch (data[0]) {
                            '"' => {
                                if (!mem.endsWith(u8, data, "\"")) {
                                    return Error.InvalidToken;
                                }
                                const str = mem.trim(u8, data, "\"");
                                try value_list.append(string(str));
                            },
                            't', 'f' => {
                                try value_list.append(try boolean(data));
                            },
                            else => {
                                try value_list.append(try number(data));
                            }
                        }
                    }

                    return listItem(key, try value_list.toOwnedSlice());
                },
                '"' => {
                    _ = try p.next();
                    const token = try tokenStr(p, '"');
                    return pairItem(key, string(token));
                },
                't', 'f' => {
                    const token = try sanitize(try tokenStr(p, '\n'));
                    return pairItem(key, try boolean(token));
                },
                else => {
                    const token = try sanitize(try tokenStr(p, '\n'));
                    return pairItem(key, try number(token));
                }
            }
        }

        return Error.UnexpectedEOF;
    }

    fn tokenStr(p: *Parser, delimiter: u8) !Str {
        const begin = p.cursor();
        while (!p.eat(delimiter)) { _ = try p.next(); }
        const end = p.cursor() - 1;

        return try p.peekStr(begin, end);
    }

    fn listItem(key: Str, value: []Value) Item {
        const list = List {.name = key, .values = value};
        return .{.list = list};
    }

    fn pairItem(key: Str, value: Value) Item {
        const pair = Pair {.name = key, .value = value};
        return Item {.pair = pair};
    }

    fn number(token: Str) !Value {
        const value = try std.fmt.parseInt(isize, token, 10);
        return Value {.number = value};
    }

    fn boolean(token: Str) !Value {
        if (mem.eql(u8, token, "true")) return Value {.boolean = true}
        else if (mem.eql(u8, token, "false")) return Value {.boolean = false}
        else return Error.InvalidToken;
    }

    fn string(token: Str) Value { return Value {.string = token}; }
};

const Comments = struct {
    /// # Skips Comments
    fn skip(p: *Parser) !void {
        _ = p.eatSp();
        while (try parse(p) != null) { _ = p.eatSp(); }
    }

    /// # Until End of Comment or EOF
    fn parse(p: *Parser) !?void {
        if (!p.eat('#')) return null;
        while (p.peek() != null and !p.eat('\n')) { _ = try p.next(); }
    }
};

/// # Keyword And Value Tokens
fn sanitize(token: Str) !Str {
    const data = mem.trim(u8, token, &ascii.whitespace);
    for (data) |char| {
        if (ascii.isWhitespace(char)) return Error.InvalidToken;
    }
    return data;
}

/// # Keyword Characters
fn validate(keyword: Str) !Str {
    for (keyword) |char| {
        if (ascii.isAlphanumeric(char) or char == '_') continue
        else return Error.InvalidKeyword;
    }

    return keyword;
}

test "App Config Demo" {
    const src_static =
    \\ # This is a comment
    \\ # Following code is a flat section
    \\ global {
    \\     # Following items are pair
    \\     prop_1 = 100
    \\     prop_2 = true
    \\     prop_3 = "hello"
    \\
    \\     # Following item is a list
    \\     prop_4 = [100, true, "hello"]
    \\ }
    \\
    \\ # Following code is a nested section
    \\ project {
    \\     # Following code is a nested section
    \\     one {
    \\         one { prop = "hello" }
    \\     }
    \\
    \\     # Following code is a flat section
    \\     two {
    \\         prop = [100, true, "hello"]
    \\         # foo = "bar"
    \\         fool2 = "baz"
    \\     }
    \\ }
    \\
    \\ applet {
    \\     proj_1 {
    \\         host_name = "example.com"
    \\         shared_object = "../proj-1/zig-out/lib/lib-proj-1.so"
    \\     }
    \\ }
    ;

    const heap = testing.allocator;

    const src_data = try heap.alloc(u8, src_static.len);
    errdefer heap.free(src_data);

    mem.copyForwards(u8, src_data, src_static);

    // Feeding file content manually because `init()` expects file path
    var p = Parser.init(src_data);
    const data = try SourceContent.parse(heap, &p);
    Self.so = .{.heap = heap, .env = null, .src = src_data, .secs = data};
    defer Self.deinit();

    try testing.expectEqual(100, try getInt(u8, "global.prop_1"));
    try testing.expectEqual(100, try getInt(i16, "global.prop_1"));
    try testing.expectEqual(100, try getInt(u32, "global.prop_1"));
    try testing.expectEqual(100, try getInt(isize, "global.prop_1"));
    try testing.expectEqual(100, try getInt(usize, "global.prop_1"));
    try testing.expectEqual(true, try getBool("global.prop_2"));
    try testing.expect(mem.eql(u8, "hello", try getStr("global.prop_3")));

    const items = try getList("global.prop_4");
    try testing.expectEqual(100, items[0].number);
    try testing.expectEqual(true, items[1].boolean);
    try testing.expect(mem.eql(u8, "hello", items[2].string));

    try testing.expect(
        mem.eql(u8, "hello", try getStr("project.one.one.prop"))
    );

    const nested_items = try getList("project.two.prop");
    try testing.expectEqual(100, nested_items[0].number);
    try testing.expectEqual(true, nested_items[1].boolean);
    try testing.expect(mem.eql(u8, "hello", nested_items[2].string));
}
