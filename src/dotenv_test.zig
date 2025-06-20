const std = @import("std");
const testing = std.testing;

const dotenv = @import("dotenv.zig");

test "parse single line" {
    const alloc = testing.allocator;

    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();

    if (try env.parseLine("FOO=bar", .{})) |kv| {
        try env.map.put(kv.key, kv.value);
    }
    try std.testing.expectEqualStrings("bar", env.get("FOO").?);
}

test "parse quoted and escaped value" {
    const alloc = testing.allocator;

    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();

    if (try env.parseLine("BAR=\"baz\\nbat\"", .{})) |kv| {
        try env.map.put(kv.key, kv.value);
    }

    try std.testing.expectEqualStrings("baz\nbat", env.get("BAR").?);
}

test "parse empty and comment lines" {
    const alloc = testing.allocator;

    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();

    try env.parse(
        \\# comment
        \\
        \\FOO=1
        \\BAR=2
        \\# another comment
    , .{});
    try std.testing.expectEqualStrings("1", env.get("FOO").?);
    try std.testing.expectEqualStrings("2", env.get("BAR").?);
    try std.testing.expect(env.get("BAZ") == null);
}

test "parse file and keys" {
    const alloc = testing.allocator;

    // Write a temp .env file
    const test_content =
        \\FOO=abc
        \\BAR="def ghi"
        \\# Test
        \\BAZ=xyz
    ;
    const tmp_path = "test.env";
    {
        var file = try std.fs.cwd().createFile(tmp_path, .{ .read = true });
        defer file.close();
        _ = try file.write(test_content);
    }
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();
    try env.parseFile(tmp_path, .{});

    const keys = try env.keys();
    defer alloc.free(keys);

    var found: usize = 0;
    for (keys) |k| {
        if (std.mem.eql(u8, k, "FOO")) found += 1;
        if (std.mem.eql(u8, k, "BAR")) found += 1;
        if (std.mem.eql(u8, k, "BAZ")) found += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), found);
    try std.testing.expectEqualStrings("abc", env.get("FOO").?);
    try std.testing.expectEqualStrings("def ghi", env.get("BAR").?);
    try std.testing.expectEqualStrings("xyz", env.get("BAZ").?);
}

test "vars returns all DotenvVar structs" {
    const alloc = testing.allocator;

    var env = dotenv.Dotenv.init(alloc);
    defer env.deinit();

    try env.set("A", "1");
    try env.set("B", "2");

    const vars = try env.values();
    defer alloc.free(vars);

    var found_a = false;
    var found_b = false;
    for (vars) |item| {
        if (std.mem.eql(u8, item.key, "A") and std.mem.eql(u8, item.value, "1")) found_a = true;
        if (std.mem.eql(u8, item.key, "B") and std.mem.eql(u8, item.value, "2")) found_b = true;
    }

    try std.testing.expect(found_a and found_b);

    const check_content =
        \\A=1
        \\B=2
        \\
    ;
    const res = try env.toString(.{});
    defer alloc.free(res);

    try std.testing.expectEqualStrings(check_content, res);
}
