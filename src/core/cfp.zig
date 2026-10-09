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
const Io = std.Io;
const mem = std.mem;
const ascii = std.ascii;
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = mem.Allocator;
const StringHashMap = std.StringHashMap;

const utils = @import("./utils.zig");
const Parser = @import("./parser.zig");


const Str = []const u8;

const Error = error {
    InvalidQuery,
    InvalidToken,
    InvalidFormat,
    UnexpectedEOF,
    InvalidKeyword,
    UnexpectedDataType
};

const ParseError = error {
    InvalidQuery,
    InvalidToken,
    InvalidFormat,
    UnexpectedEOF,
    InvalidKeyword,
    UnexpectedDataType,
    InvalidOffsetRange,
    UnexpectedCharacter,
    Overflow,
    InvalidCharacter,
    OutOfMemory
};

const SingletonObject = struct {
    heap: Allocator,
    env: ?u8,
    src: Str,
    secs: []Section,
    sections: StringHashMap(*Section),
    pairs: StringHashMap(*Pair),
    lists: StringHashMap(*List)
};

const Index = struct {
    sections: StringHashMap(*Section),
    pairs: StringHashMap(*Pair),
    lists: StringHashMap(*List)
};

fn buildIndex(heap: Allocator, secs: []Section) !Index {
    var index = Index {
        .sections = StringHashMap(*Section).init(heap),
        .pairs = StringHashMap(*Pair).init(heap),
        .lists = StringHashMap(*List).init(heap)
    };
    errdefer freeIndex(heap, &index.sections, &index.pairs, &index.lists);

    try indexSections(heap, secs, "", &index);
    return index;
}

fn indexSections(
    heap: Allocator,
    secs: []Section,
    prefix: Str,
    index: *Index
) !void {
    for (secs) |*section| {
        const section_path = try pathName(heap, prefix, section.name);
        const section_is_new = index.sections.get(section_path) == null;
        if (section_is_new) {
            index.sections.put(section_path, section) catch |err| {
                heap.free(section_path);
                return err;
            };
        }
        defer if (!section_is_new) heap.free(section_path);

        switch (section.data) {
            .flat => |items| {
                for (items) |*item| {
                    const item_path = try pathName(heap, section_path, switch (item.*) {
                        .pair => |pair| pair.name,
                        .list => |list| list.name
                    });

                    // Pairs and lists are indexed separately so a query
                    // resolves by both path and kind, matching a config that
                    // reuses the same name for a pair and a list.
                    const known = switch (item.*) {
                        .pair => |*pair| index.pairs.get(item_path) != null or
                            blk: { index.pairs.put(item_path, pair) catch |err| {
                                heap.free(item_path);
                                return err;
                            }; break :blk false; },
                        .list => |*list| index.lists.get(item_path) != null or
                            blk: { index.lists.put(item_path, list) catch |err| {
                                heap.free(item_path);
                                return err;
                            }; break :blk false; },
                    };
                    if (known) heap.free(item_path);
                }
            },
            .nested => |children| try indexSections(
                heap, children, section_path, index
            )
        }
    }
}

fn pathName(heap: Allocator, prefix: Str, name: Str) !Str {
    if (prefix.len == 0) return heap.dupe(u8, name);
    return std.fmt.allocPrint(heap, "{s}.{s}", .{prefix, name});
}

fn freeIndex(
    heap: Allocator,
    sections: *StringHashMap(*Section),
    pairs: *StringHashMap(*Pair),
    lists: *StringHashMap(*List)
) void {
    var section_keys = sections.keyIterator();
    while (section_keys.next()) |key| heap.free(key.*);
    sections.deinit();

    var pair_keys = pairs.keyIterator();
    while (pair_keys.next()) |key| heap.free(key.*);
    pairs.deinit();

    var list_keys = lists.keyIterator();
    while (list_keys.next()) |key| heap.free(key.*);
    lists.deinit();
}

fn installSingleton(
    heap: Allocator,
    env: ?u8,
    src: Str,
    secs: []Section
) !void {
    const index = buildIndex(heap, secs) catch |err| {
        for (secs) |*section| free(heap, section);
        heap.free(secs);
        return err;
    };

    Self.so = .{
        .heap = heap,
        .env = env,
        .src = src,
        .secs = secs,
        .sections = index.sections,
        .pairs = index.pairs,
        .lists = index.lists,
    };
}

var so: ?SingletonObject = null;

const Self = @This();

pub const Option = struct { env: ?u8 = null, abs_path: Str };

/// # Initializes a Singleton
/// - `opt.env` - An optional environment identifier `Dev`, `Prod` etc.
/// - `opt.abs_path` - An absolute app configuration file path
pub fn init(io: Io, heap: Allocator, opt: Option) !void {
    if (Self.so != null) @panic("Initialize Only Once Per Process!");

    const src_data = try utils.loadFile(io, heap, opt.abs_path);
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

    installSingleton(heap, opt.env, src_data, data) catch |err| {
        heap.free(src_data);
        return err;
    };
}

/// # Destroys the Singleton
pub fn deinit() void {
    const sop = Self.iso();

    freeIndex(sop.heap, &sop.sections, &sop.pairs, &sop.lists);
    for (sop.secs) |*sec| free(sop.heap, sec);

    sop.heap.free(sop.secs);
    sop.heap.free(sop.src);
    so = null;
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
    if (@as(Value, v) != Value.number) return Error.UnexpectedDataType;

    return std.math.cast(T, v.number) orelse Error.UnexpectedDataType;
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
    const pair = iso().pairs.get(query) orelse return Error.InvalidQuery;
    return pair.value;
}

/// # Extracts List Values
pub fn getList(query: Str) ![]Value {
    const list = iso().lists.get(query) orelse return Error.InvalidQuery;
    return list.values;
}

/// # Extracts Flat Data Items
/// **Remarks:** Use when properties are only known at runtime.
/// e.g., `foo {...}` could have any number of user defined item.
pub fn getProperties(query: Str) ?[]Item {
    const section = iso().sections.get(query) orelse return null;
    return switch (section.data) {
        .flat => |items| items,
        .nested => null
    };
}

/// # Extracts Nested Data Sections
/// **Remarks:** Use when sections are only known at runtime.
/// e.g., `foo {...}` could have any number of user defined section.
pub fn getSections(query: Str) ?[]Section {
    const section = iso().sections.get(query) orelse return null;
    return switch (section.data) {
        .nested => |sections| sections,
        .flat => null
    };
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

    fn parse(heap: Allocator, p: *Parser) ParseError![]Section {
        const data = try parseBody(heap, p, false);
        return switch (data) {
            .nested => |sections| sections,
            .flat => Error.InvalidFormat
        };
    }

    fn parseBody(
        heap: Allocator,
        p: *Parser,
        allow_close: bool
    ) ParseError!Data {
        var sections: ArrayList(Section) = .empty;
        errdefer {
            for (sections.items) |*sec| free(heap, sec);
            sections.deinit(heap);
        }

        try Comments.skip(p);
        while (p.peek() != null) {
            if (p.eat('}')) {
                if (!allow_close) return Error.InvalidFormat;
                try Comments.skip(p);
                return .{.nested = try sections.toOwnedSlice(heap)};
            }

            switch (try keyword(p)) {
                .section => |key| {
                    const child = try SourceContent.nested(heap, p, key);
                    try sections.append(heap, child);
                },
                .property => |key| {
                    if (!allow_close) return Error.InvalidFormat;

                    var items: ArrayList(Item) = .empty;
                    errdefer {
                        for (items.items) |*item| {
                            if (item.* == .list) heap.free(item.list.values);
                        }
                        items.deinit(heap);
                    }

                    try SourceContent.flat(heap, p, &items, key);
                    return .{.flat = try items.toOwnedSlice(heap)};
                }
            }
        }

        return if (allow_close) Error.UnexpectedEOF
        else .{.nested = try sections.toOwnedSlice(heap)};
    }

    fn keyword(p: *Parser) !Keyword {
        defer _ = p.eatSp();

        const token = try keywordStr(p);
        const key = try sanitizeKeyword(token);
        const tail = try p.peekStr(p.cursor() - 1, p.cursor());

        return if (mem.eql(u8, tail, "=")) Keyword { .property = key }
        else Keyword { .section = key };
    }

    fn keywordStr(p: *Parser) !Str {
        const begin = p.cursor();
        while (p.peek()) |char| {
            if (char == '{' or char == '=') {
                _ = try p.next();
                return try p.peekStr(begin, p.cursor() - 1);
            }
            _ = try p.next();
        }
        return Error.UnexpectedEOF;
    }

    fn nested(heap: Allocator, p: *Parser, name: Str) ParseError!Section {
        return .{.name = name, .data = try parseBody(heap, p, true)};
    }

    fn flat(
        heap: Allocator,
        p: *Parser,
        items: *ArrayList(Item),
        name: Str
    ) !void {
        try items.append(heap, try Property.getItem(heap, p, name));
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

                    var value_list: ArrayList(Value) = .empty;
                    errdefer value_list.deinit(heap);

                    while(tokens.peek() != null) {
                        const token = tokens.next().?;
                        const data = mem.trim(u8, token, &ascii.whitespace);

                        if (data.len == 0) return Error.InvalidToken;

                        switch (data[0]) {
                            '"' => {
                                if (!mem.endsWith(u8, data, "\"")) {
                                    return Error.InvalidToken;
                                }
                                const str = mem.trim(u8, data, "\"");
                                try value_list.append(heap, string(str));
                            },
                            't', 'f' => {
                                try value_list.append(heap, try boolean(data));
                            },
                            else => {
                                try value_list.append(heap, try number(data));
                            }
                        }
                    }

                    return listItem(key, try value_list.toOwnedSlice(heap));
                },
                '"' => {
                    _ = try p.next();
                    const token = try tokenStr(p, '"');
                    return pairItem(key, string(token));
                },
                't', 'f' => {
                    const token = try sanitizeValue(try bareStr(p));
                    return pairItem(key, try boolean(token));
                },
                else => {
                    const token = try sanitizeValue(try bareStr(p));
                    return pairItem(key, try number(token));
                }
            }
        }

        return Error.UnexpectedEOF;
    }

    fn tokenStr(p: *Parser, delimiter: u8) !Str {
        const begin = p.cursor();
        while (p.peek()) |char| {
            _ = try p.next();
            if (char == delimiter) return try p.peekStr(begin, p.cursor() - 1);
        }
        return Error.UnexpectedEOF;
    }

    /// # Bare Value Token
    /// - Reads until a newline, inline comment `#`, closing brace `}`,
    ///   or end of source. Unlike `tokenStr()`, it never fails at EOF.
    fn bareStr(p: *Parser) !Str {
        const begin = p.cursor();
        while (p.peek()) |char| {
            if (char == '\n' or char == '#' or char == '}') break;
            _ = try p.next();
        }

        return try p.peekStr(begin, p.cursor());
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
        while (p.peek()) |char| {
            _ = try p.next();
            if (char == '\n') break;
        }
    }
};

/// # Keyword Characters
fn sanitizeKeyword(token: Str) !Str {
    const data = mem.trim(u8, token, &ascii.whitespace);
    if (data.len == 0) return Error.InvalidKeyword;

    for (data) |char| {
        if (ascii.isAlphanumeric(char) or char == '_') continue;
        if (ascii.isWhitespace(char)) return Error.InvalidToken;
        return Error.InvalidKeyword;
    }

    return data;
}

/// # Keyword And Value Tokens
fn sanitizeValue(token: Str) !Str {
    const data = mem.trim(u8, token, &ascii.whitespace);
    for (data) |char| {
        if (ascii.isWhitespace(char)) return Error.InvalidToken;
    }
    return data;
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
    try installSingleton(heap, null, src_data, data);
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

test "MalformedInputs" {
    const expectError = testing.expectError;
    const heap = testing.allocator;

    // Truncated section must fail instead of silently parsing
    {
        const src_data = try heap.dupe(u8, "global { prop = 100");
        errdefer heap.free(src_data);

        var p = Parser.init(src_data);
        try expectError(Error.UnexpectedEOF, SourceContent.parse(heap, &p));
        heap.free(src_data);
    }

    // Empty list element must be rejected, not crash
    {
        const src_data = try heap.dupe(u8, "global { prop = [ , 100] }");
        errdefer heap.free(src_data);

        var p = Parser.init(src_data);
        try expectError(Error.InvalidToken, SourceContent.parse(heap, &p));
        heap.free(src_data);
    }

    // Stray closing brace at top level
    {
        const src_data = try heap.dupe(u8, "} global { prop = 100 }");
        errdefer heap.free(src_data);

        var p = Parser.init(src_data);
        try expectError(Error.InvalidFormat, SourceContent.parse(heap, &p));
        heap.free(src_data);
    }

    // A failed parse after a successful list item must not leak
    {
        const src_data = try heap.dupe(u8, "global { prop = [1, 2]\nbroken = \"unclosed");
        errdefer heap.free(src_data);

        var p = Parser.init(src_data);
        try expectError(Error.UnexpectedEOF, SourceContent.parse(heap, &p));
        heap.free(src_data);
    }
}

test "BareValuesCommentsAndQueries" {
    const expectError = testing.expectError;
    const expectEqual = testing.expectEqual;
    const heap = testing.allocator;

    const src =
        \\global {
        \\    prop_1 = 100 # inline comment
        \\    big = 300
        \\    neg = -5
        \\    prop_2 = true
        \\}
    ;
    // Note: no trailing newline and `}` shares the line - must still parse

    const src_data = try heap.dupe(u8, src);
    var p = Parser.init(src_data);

    const data = SourceContent.parse(heap, &p) catch |err| {
        heap.free(src_data);
        return err;
    };

    try installSingleton(heap, null, src_data, data);
    defer Self.deinit();

    try expectEqual(@as(u8, 100), try getInt(u8, "global.prop_1"));
    try expectEqual(@as(i16, -5), try getInt(i16, "global.neg"));
    try testing.expect(try getBool("global.prop_2"));

    // Out-of-range integers must error instead of panicking
    try expectError(Error.UnexpectedDataType, getInt(u8, "global.big"));
    try expectError(Error.UnexpectedDataType, getInt(u8, "global.neg"));

    // Malformed queries must return errors, not crash
    try expectError(Error.InvalidQuery, getValue("global"));
    try expectError(Error.InvalidQuery, getValue("global."));
    try expectError(Error.InvalidQuery, getValue("global.prop.extra"));
    try expectError(Error.InvalidQuery, getValue(""));
}

test "DeinitResetsSingleton" {
    const heap = testing.allocator;

    const src_data = try heap.dupe(u8, "global { prop = 100 }");
    var p = Parser.init(src_data);

    const data = SourceContent.parse(heap, &p) catch |err| {
        heap.free(src_data);
        return err;
    };

    try installSingleton(heap, null, src_data, data);
    Self.deinit();

    try testing.expect(Self.so == null);
}

test "DuplicatePairAndListNames" {
    const expectError = testing.expectError;
    const heap = testing.allocator;

    // A pair and a list may share the same name in a flat section; each kind
    // must stay independently queryable.
    const src_data = try heap.dupe(u8, "demo { prop = 100\nprop = [1, 2] }");

    var p = Parser.init(src_data);
    const data = SourceContent.parse(heap, &p) catch |err| {
        heap.free(src_data);
        return err;
    };

    try installSingleton(heap, null, src_data, data);
    defer Self.deinit();

    try testing.expectEqual(@as(isize, 100), (try getValue("demo.prop")).number);

    const values = try getList("demo.prop");
    try testing.expectEqual(@as(isize, 1), values[0].number);
    try testing.expectEqual(@as(isize, 2), values[1].number);

    // Kind mismatches stay ordinary errors
    try expectError(Error.InvalidQuery, getList("demo.nope"));
}
