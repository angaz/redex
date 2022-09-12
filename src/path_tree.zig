const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

const PathBuilder = struct {
    path_rev: []u8 = undefined,
    p_len: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        initial_key_len: usize,
    ) !@This() {
        return @This(){
            .path_rev = try allocator.alloc(u8, initial_key_len),
            .p_len = 0,
        };
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.path_rev);
    }

    pub fn push(self: *@This(), allocator: std.mem.Allocator, key: []const u8) !void {
        if (self.path_rev.len < self.p_len + key.len) {
            self.path_rev = try allocator.realloc(self.path_rev, self.path_rev.len * 2);
        }

        var i = key.len;
        while (i > 0) {
            i -= 1;
            self.path_rev[self.p_len] = key[i];
            self.p_len += 1;
        }
    }

    pub fn path(self: *@This(), allocator: std.mem.Allocator) ![]u8 {
        var p = try allocator.alloc(u8, self.p_len);

        var i: usize = 0;
        while (i < self.p_len) {
            p[i] = self.path_rev[self.p_len - i - 1];
            i += 1;
        }

        return p;
    }
};

pub fn PathTree(comptime T: type, comptime order: fn (T, T) std.math.Order) type {
    return struct {
        pub const Node = struct {
            parent: ?*@This() = null,
            first_child: ?*@This() = null,

            next_sibling: ?*@This() = null,
            previous_sibling: ?*@This() = null,

            data: T,

            pub fn path(
                self: *@This(),
                allocator: std.mem.Allocator,
                initial_key_len: usize,
            ) ![]u8 {
                var builder = try PathBuilder.init(
                    allocator,
                    initial_key_len,
                );
                defer builder.deinit(allocator);

                var current_node: ?*@This() = self;
                while (current_node) |node| {
                    try builder.push(allocator, node.data);
                    current_node = node.parent;
                }

                return builder.path(allocator);
            }

            pub fn is_leaf(self: *@This()) bool {
                return self.first_child == null;
            }

            pub fn is_first_sibling(self: *@This()) bool {
                return self.previous_sibling == null;
            }

            pub fn is_top_level(self: @This()) bool {
                return self.parent == null;
            }

            pub fn is_root(self: *@This()) bool {
                return (self.is_top_level() and self.is_first_sibling());
            }

            pub fn find_first_sibling(self: *@This()) *@This() {
                if (self.is_first_sibling()) {
                    return self;
                }

                var current_node = self;
                while (current_node.previous_sibling) |previous| {
                    current_node = previous;
                }

                return current_node;
            }

            fn insert_previous_sibling(self: *@This(), n: *@This()) *@This() {
                n.previous_sibling = self.previous_sibling;
                n.next_sibling = self;
                if (self.previous_sibling) |previous_sibling| {
                    previous_sibling.next_sibling = n;
                }
                self.previous_sibling = n;

                return n;
            }

            fn insert_next_sibling(self: *@This(), n: *@This()) *@This() {
                n.previous_sibling = self;
                n.next_sibling = self.next_sibling;
                if (self.next_sibling) |next_sibling| {
                    next_sibling.previous_sibling = n;
                }
                self.next_sibling = n;

                return n;
            }

            pub fn insert_sibling(self: *@This(), n: *@This()) *@This() {
                n.parent = self.parent;

                var current_node = self.find_first_sibling();
                while (true) {
                    switch (order(n.data, current_node.data)) {
                        .eq => return current_node,
                        .lt => return current_node.insert_previous_sibling(n),
                        .gt => {
                            if (current_node.next_sibling) |next_sibling| {
                                current_node = next_sibling;
                            } else {
                                return current_node.insert_next_sibling(n);
                            }
                        },
                    }
                }
            }

            pub fn insert_child(self: *@This(), n: *@This()) *@This() {
                if (self.first_child) |first_child| {
                    var new = first_child.insert_sibling(n);

                    if (new.is_first_sibling()) {
                        self.first_child = new;
                    }

                    return new;
                }

                self.first_child = n;
                n.parent = self;
                return n;
            }

            pub fn detatch_node(self: *@This()) *@This() {
                if (self.parent) |parent| {
                    if (parent.first_node == self) {
                        parent.first_node = self.next_sibling;
                    }
                }

                if (self.next_sibling) |next_sibling| {
                    next_sibling.previous_sibling = self.previous_sibling;
                }

                if (self.previous_sibling) |previous_sibling| {
                    previous_sibling.next_sibling = self.next_sibling;
                }

                return self;
            }

            pub fn deinit_tree(self: *@This(), allocator: std.mem.Allocator) void {
                var children = self.list();
                while (children.next()) |child| {
                    child.deinit_tree(allocator);
                }

                allocator.destroy(self);
            }

            pub fn init(allocator: std.mem.Allocator, data: T) !*@This() {
                var n = try allocator.create(@This());
                n.first_child = null;
                n.next_sibling = null;
                n.parent = null;
                n.previous_sibling = null;
                n.data = data;
                return n;
            }

            const ListIterator = struct {
                current_node: ?*Node,

                pub fn next(self: *@This()) ?*Node {
                    if (self.current_node) |n| {
                        self.current_node = n.next_sibling;
                        return n;
                    }
                    return null;
                }
            };

            pub fn list(self: *@This()) ListIterator {
                return ListIterator{ .current_node = self.first_child };
            }

            pub fn iter(self: *@This()) ListIterator {
                return ListIterator{ .current_node = self };
            }

            pub fn siblings_left(self: *@This(), n_left: usize) *@This() {
                var current_node = self;

                var i: usize = 0;
                while (i < n_left) : (i += 1) {
                    if (current_node.previous_sibling) |n| {
                        current_node = n;
                    } else {
                        return current_node;
                    }
                }

                return current_node;
            }

            pub fn siblings_right(self: *@This(), n_right: usize) *@This() {
                var current_node = self;

                var i: usize = 0;
                while (i < n_right) : (i += 1) {
                    if (current_node.next_sibling) |n| {
                        current_node = n;
                    } else {
                        return current_node;
                    }
                }

                return current_node;
            }

            pub fn print(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.is_leaf())
                    std.debug.print("{s}\n", .{self.path(allocator, 64, ':')});
                var children = self.list();
                while (children.next()) |child| {
                    child.print(allocator);
                }
            }
        };

        root: ?*Node,

        pub fn init() @This() {
            return @This(){
                .root = null,
            };
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.root) |root| {
                root.deinit_tree(allocator);
            }
        }

        pub fn insert_path(
            self: *@This(),
            allocator: std.mem.Allocator,
            path: []const u8,
            separators: []const u8,
        ) !*Node {
            var it = tokenize_key(u8, path, separators);
            var current_node = self.root;

            if (it.next()) |name| {
                var n = try Node.init(allocator, name);

                if (current_node) |cn| {
                    var new = cn.insert_sibling(n);
                    if (n != new) {
                        allocator.destroy(n);
                    }
                    if (new.is_first_sibling()) {
                        self.root = new;
                    }
                    current_node = new;
                } else {
                    self.root = n;
                    current_node = n;
                }
            }

            while (it.next()) |name| {
                var n = try Node.init(allocator, name);

                if (current_node) |cn| {
                    var new = cn.insert_child(n);
                    if (n != new) {
                        allocator.destroy(n);
                    }
                    current_node = new;
                } else {
                    unreachable;
                }
            }

            return current_node.?;
        }

        pub fn print(self: @This(), allocator: std.mem.Allocator) void {
            var children = self.root.list();
            while (children.next()) |child| {
                child.print(allocator);
            }
        }
    };
}

/// Basically copy-pasta from std.mem.tokenize,
/// but keeps the separator.
pub fn KeyPathIterator(comptime T: type) type {
    return struct {
        buffer: []const T,
        delimiter_bytes: []const T,
        index: usize,

        const Self = @This();

        /// Returns a slice of the current token, or null if tokenization is
        /// complete, and advances to the next token.
        pub fn next(self: *Self) ?[]const T {
            const result = self.peek() orelse return null;
            self.index += result.len;
            return result;
        }

        /// Returns a slice of the current token, or null if tokenization is
        /// complete. Does not advance to the next token.
        pub fn peek(self: *Self) ?[]const T {
            // move to beginning of token
            while (self.index < self.buffer.len and self.isSplitByte(self.buffer[self.index])) : (self.index += 1) {}
            const start = self.index;
            if (start == self.buffer.len) {
                return null;
            }

            // move to token
            var end = start;
            while (end < self.buffer.len) : (end += 1) {
                if (self.isSplitByte(self.buffer[end])) {
                    end += 1;
                    break;
                }
            }

            return self.buffer[start..end];
        }

        /// Returns a slice of the remaining bytes. Does not affect iterator state.
        pub fn rest(self: Self) []const T {
            // move to beginning of token
            var index: usize = self.index;
            while (index < self.buffer.len and self.isSplitByte(self.buffer[index])) : (index += 1) {}
            return self.buffer[index..];
        }

        /// Resets the iterator to the initial token.
        pub fn reset(self: *Self) void {
            self.index = 0;
        }

        fn isSplitByte(self: Self, byte: T) bool {
            for (self.delimiter_bytes) |delimiter_byte| {
                if (byte == delimiter_byte) {
                    return true;
                }
            }
            return false;
        }
    };
}
fn tokenize_key(comptime T: type, buffer: []const T, delimiter_bytes: []const T) KeyPathIterator(T) {
    return .{
        .index = 0,
        .buffer = buffer,
        .delimiter_bytes = delimiter_bytes,
    };
}

fn u8_order(left: []const u8, right: []const u8) std.math.Order {
    return std.mem.order(u8, left, right);
}
pub const U8PathTree = PathTree([]const u8, u8_order);

test "key tree" {
    var rn = U8PathTree.Node{ .data = "/root/" };
    var kt = U8PathTree{ .root = &rn };

    try testing.expect(std.mem.eql(u8, kt.root.data, "/root/"));
    var cn = kt.root;
    var n = U8PathTree.Node{ .data = "movies" };
    _ = cn.insert_child(&n);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "movies"));
    var n2 = U8PathTree.Node{ .data = "actors" };
    _ = cn.insert_child(&n2);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "movies"));
    var n3 = U8PathTree.Node{ .data = "directors" };
    _ = cn.insert_child(&n3);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    var n4 = U8PathTree.Node{ .data = "vfx" };
    _ = cn.insert_child(&n3);
    _ = cn.insert_child(&n4);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.next_sibling.?.data, "vfx"));

    var n5 = U8PathTree.Node{ .data = "12345" };
    _ = n2.insert_child(&n5);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.next_sibling.?.data, "vfx"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.first_child.?.data, "12345"));
}
