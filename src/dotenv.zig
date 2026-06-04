const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Allocator = std.mem.Allocator;

const StringArrayMap = std.array_hash_map.String([]const u8);

pub const Dotenv = struct {
    map: StringArrayMap,
    options: Options,
    alloc: Allocator,

    const Self = @This();

    pub const Options = struct {
        separator: u8 = '=',
        comment: u8 = '#',
        trim_chars: []const u8 = " \t\r\n",
    };

    pub const VarData = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn init(alloc: Allocator, options: Options) Self {
        return .{
            .map = .empty,
            .options = options,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }
        self.map.deinit(self.alloc);
    }

    pub fn withOptions(self: *Self, options: Options) void {
        self.options = options;
    }

    pub fn parse(self: *Self, content: []const u8) !void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.alloc.free(entry.key_ptr.*);
            self.alloc.free(entry.value_ptr.*);
        }

        self.map.clearRetainingCapacity();

        var i: usize = 0;
        while (i < content.len) {
            var line_end = i;
            while (line_end < content.len and content[line_end] != '\n' and content[line_end] != '\r') : (line_end += 1) {}

            const line = content[i..line_end];
            i = line_end;
            while (i < content.len and (content[i] == '\n' or content[i] == '\r')) : (i += 1) {}

            if (try self.parseLine(line)) |envvar| {
                try self.map.put(self.alloc, envvar.key, envvar.value);
            }
        }
    }

    pub fn parseLine(self: *Self, line: []const u8) !?VarData {
        const options = self.options;

        const trimmed = mem.trim(u8, line, options.trim_chars);
        if (trimmed.len == 0 or trimmed[0] == options.comment) return null;

        const eq_index = mem.indexOfScalar(u8, trimmed, options.separator) orelse return null;
        const key = mem.trim(u8, trimmed[0..eq_index], options.trim_chars);
        var value = mem.trim(u8, trimmed[eq_index + 1 ..], options.trim_chars);

        if (key.len == 0) return null;

        // Remove quotes and handle escapes
        if (value.len > 1 and (value[0] == '"' or value[0] == '\'')) {
            const quote = value[0];
            if (value[value.len - 1] == quote) {
                value = value[1 .. value.len - 1];
            }

            var buf = try self.alloc.alloc(u8, value.len);
            defer self.alloc.free(buf);

            var j: usize = 0;
            var k: usize = 0;
            while (k < value.len) : (k += 1) {
                if (value[k] == '\\' and k + 1 < value.len) {
                    k += 1;
                    switch (value[k]) {
                        '\\' => buf[j] = '\\',
                        'n' => buf[j] = '\n',
                        'r' => buf[j] = '\r',
                        't' => buf[j] = '\t',
                        '"' => buf[j] = '"',
                        '\'' => buf[j] = '\'',
                        else => buf[j] = value[k],
                    }
                } else {
                    buf[j] = value[k];
                }
                j += 1;
            }

            const key_copy = try self.alloc.dupe(u8, key);
            const value_copy = try self.alloc.dupe(u8, buf[0..j]);

            return .{
                .key = key_copy,
                .value = value_copy,
            };
        }

        const key_copy = try self.alloc.dupe(u8, key);
        const value_copy = try self.alloc.dupe(u8, value);

        return .{
            .key = key_copy,
            .value = value_copy,
        };
    }

    pub fn parseFile(self: *Self, io: Io, path: []const u8) !void {
        const cwd = std.Io.Dir.cwd();
        var file = try cwd.openFile(io, path, .{});
        defer file.close(io);

        const stat = try file.stat(io);
        const content = try self.alloc.alloc(u8, stat.size);
        defer self.alloc.free(content);

        _ = try file.readPositionalAll(io, content, 0);
        try self.parse(content);
    }

    /// Set a kv data
    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        if (self.map.fetchOrderedRemove(key)) |entry| {
            self.alloc.free(entry.key);
            self.alloc.free(entry.value);
        }

        const key_copy = try self.alloc.dupe(u8, key);
        const value_copy = try self.alloc.dupe(u8, value);
        try self.map.put(self.alloc, key_copy, value_copy);
    }

    pub fn get(self: Self, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        if (self.map.fetchOrderedRemove(key)) |entry| {
            self.alloc.free(entry.key);
            self.alloc.free(entry.value);

            return true;
        }

        return false;
    }

    pub fn has(self: Self, key: []const u8) bool {
        return self.map.contains(key);
    }

    pub fn count(self: Self) usize {
        return self.map.count();
    }

    pub fn isEmpty(self: Self) bool {
        return self.map.count() == 0;
    }

    pub fn keys(self: Self) ![][]const u8 {
        var keys_list = try std.ArrayList([]const u8).initCapacity(self.alloc, 0);
        defer keys_list.deinit(self.alloc);

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try keys_list.append(self.alloc, entry.key_ptr.*);
        }

        return keys_list.toOwnedSlice(self.alloc);
    }

    pub fn values(self: Self) ![]VarData {
        var vars_list = try std.ArrayList(VarData).initCapacity(self.alloc, 0);
        defer vars_list.deinit(self.alloc);

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try vars_list.append(self.alloc, .{
                .key = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }

        return vars_list.toOwnedSlice(self.alloc);
    }

    pub fn toString(self: Self) ![]u8 {
        const options = self.options;

        var list = try std.ArrayList(u8).initCapacity(self.alloc, 0);
        defer list.deinit(self.alloc);

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try list.appendSlice(self.alloc, entry.key_ptr.*);
            try list.append(self.alloc, options.separator);

            const value = entry.value_ptr.*;
            const need_quote = mem.indexOfAny(u8, value, " #") != null;
            if (need_quote) {
                try list.append(self.alloc, '"');
                for (value) |c| {
                    switch (c) {
                        '\\' => try list.appendSlice(self.alloc, "\\\\"),
                        '\n' => try list.appendSlice(self.alloc, "\\n"),
                        '\r' => try list.appendSlice(self.alloc, "\\r"),
                        '\t' => try list.appendSlice(self.alloc, "\\t"),
                        '"' => try list.appendSlice(self.alloc, "\\\""),
                        else => try list.append(self.alloc, c),
                    }
                }

                try list.append(self.alloc, '"');
            } else {
                try list.appendSlice(self.alloc, value);
            }

            try list.append(self.alloc, '\n');
        }

        return list.toOwnedSlice(self.alloc);
    }
};

test {
    _ = @import("dotenv_test.zig");
}
