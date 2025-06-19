const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;

const StringArrayMap = std.StringArrayHashMap([]const u8);

pub const Dotenv = struct {
    map: StringArrayMap,
    allocator: Allocator,

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

    pub fn init(allocator: Allocator) Self {
        return .{
            .map = StringArrayMap.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }

    pub fn parseLine(self: *Self, line: []const u8, options: Options) !?VarData {
        const trimmed = mem.trim(u8, line, options.trim_chars);
        if (trimmed.len == 0 or trimmed[0] == options.comment) return null;

        const eq_index = mem.indexOfScalar(u8, trimmed, options.separator) orelse return null;
        const key = mem.trim(u8, trimmed[0..eq_index], options.trim_chars);
        var value = mem.trim(u8, trimmed[eq_index+1..], options.trim_chars);

        if (key.len == 0) return null;

        // Remove quotes and handle escapes
        if (value.len > 1 and (value[0] == '"' or value[0] == '\'')) {
            const quote = value[0];
            if (value[value.len-1] == quote) {
                value = value[1..value.len-1];
            }

            var buf = try self.allocator.alloc(u8, value.len);
            defer self.allocator.free(buf);

            var j: usize = 0;
            var k: usize = 0;
            while (k < value.len) : (k += 1) {
                if (value[k] == '\\' and k+1 < value.len) {
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

            const key_copy = try self.allocator.dupe(u8, key);
            const value_copy = try self.allocator.dupe(u8, buf[0..j]);
            
            return .{ 
                .key = key_copy, 
                .value = value_copy,
            };
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        
        return .{ 
            .key = key_copy, 
            .value = value_copy,
        };
    }

    pub fn parse(self: *Self, content: []const u8, options: Options) !void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        self.map.clearRetainingCapacity();

        var i: usize = 0;
        while (i < content.len) {
            var line_end = i;
            while (line_end < content.len and content[line_end] != '\n' and content[line_end] != '\r') : (line_end += 1) {}
            
            const line = content[i..line_end];
            i = line_end;
            while (i < content.len and (content[i] == '\n' or content[i] == '\r')) : (i += 1) {}

            if (try self.parseLine(line, options)) |envvar| {
                try self.map.put(envvar.key, envvar.value);
            }
        }
    }

    pub fn parseFile(self: *Self, path: []const u8, options: Options) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const content = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(content);

        _ = try file.readAll(content);
        try self.parse(content, options);
    }

    pub fn set(self: *Self, key: []const u8, value: []const u8) !void {
        if (self.map.getEntry(key)) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        const key_copy = try self.allocator.dupe(u8, key);
        const value_copy = try self.allocator.dupe(u8, value);
        try self.map.put(key_copy, value_copy);
    }

    pub fn get(self: Self, key: []const u8) ?[]const u8 {
        return self.map.get(key);
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        if (self.map.getEntry(key)) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        return self.map.remove(key);
    }

    pub fn keys(self: Self) ![][]const u8 {
        var keys_list = std.ArrayList([]const u8).init(self.allocator);
        defer keys_list.deinit();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try keys_list.append(entry.key_ptr.*);
        }

        return keys_list.toOwnedSlice();
    }

    pub fn values(self: Self) ![]VarData {
        var vars_list = std.ArrayList(VarData).init(self.allocator);
        defer vars_list.deinit();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            try vars_list.append(.{
                .key = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }

        return vars_list.toOwnedSlice();
    }

    pub fn toString(self: Self, options: Options) ![]u8 {
        var list = std.ArrayList(u8).init(self.allocator);
        defer list.deinit();
        
        var it = self.map.iterator();
        while (it.next()) |entry| {
            try list.appendSlice(entry.key_ptr.*);
            try list.append(options.separator);

            const value = entry.value_ptr.*;
            const need_quote = mem.indexOfAny(u8, value, " #") != null;
            if (need_quote) {
                try list.append('"');
                for (value) |c| {
                    switch (c) {
                        '\\' => try list.appendSlice("\\\\"),
                        '\n' => try list.appendSlice("\\n"),
                        '\r' => try list.appendSlice("\\r"),
                        '\t' => try list.appendSlice("\\t"),
                        '"' => try list.appendSlice("\\\""),
                        else => try list.append(c),
                    }
                }

                try list.append('"');
            } else {
                try list.appendSlice(value);
            }

            try list.append('\n');
        }

        return list.toOwnedSlice();
    }
};

test {
    _ = @import("dotenv_test.zig");
}