const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

const PathBuilder = struct {
    path_rev: []u8 = undefined,
    p_len: usize = 0,
    separator: u8 = ':',

    pub fn init(allocator: std.mem.Allocator, separator: u8) !*@This() {
        var pb = try allocator.create(PathBuilder);

        pb.path_rev = try allocator.alloc(u8, 512);
        pb.p_len = 0;
        pb.separator = separator;

        return pb;
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.path_rev);
        allocator.destroy(self);
    }

    pub fn push(self: *@This(), key: []const u8) void {
        if (self.p_len != 0) {
            self.path_rev[self.p_len] = self.separator;
            self.p_len += 1;
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
            first_child: ?*@This() = null,
            next_sibling: ?*@This() = null,

            parent: ?*@This() = null,
            previous_sibling: ?*@This() = null,

            data: T,

            pub fn path(self: *@This(), allocator: std.mem.Allocator, separator: u8) ![]u8 {
                var builder = try PathBuilder.init(allocator, separator);
                defer builder.deinit(allocator);

                var current_node: ?*@This() = self;
                while (current_node) |node| {
                    if (node.parent == null) {
                        break;
                    }
                    builder.push(node.data);
                    current_node = node.parent;
                }

                return builder.path(allocator);
            }

            pub fn is_leaf(self: *@This()) bool {
                return self.first_child == null;
            }

            pub fn insert_child(self: *@This(), n: *@This()) *@This() {
                if (self.first_child) |first_child| {
                    var cmp = order(n.data, first_child.data);

                    if (cmp == .eq) {
                        return first_child;
                    }

                    n.parent = self;

                    if (cmp == .lt) {
                        self.first_child = n;
                        first_child.previous_sibling = n;
                        n.next_sibling = first_child;
                        return n;
                    }

                    var current_node = first_child;
                    while (current_node.next_sibling) |next_sibling| {
                        cmp = order(n.data, next_sibling.data);

                        if (cmp == .eq) {
                            return next_sibling;
                        }

                        if (cmp == .lt) {
                            current_node.next_sibling = n;
                            next_sibling.previous_sibling = n;
                            n.previous_sibling = current_node;
                            n.next_sibling = next_sibling;
                            return n;
                        }

                        current_node = next_sibling;
                    }

                    current_node.next_sibling = n;
                    n.previous_sibling = current_node;
                    return n;
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

            pub fn print(self: *@This(), allocator: std.mem.Allocator) void {
                if (self.is_leaf())
                    std.debug.print("{s}\n", .{self.path(allocator, ':')});
                var children = self.list();
                while (children.next()) |child| {
                    child.print(allocator);
                }
            }
        };

        root: *@This().Node,

        pub fn init(allocator: std.mem.Allocator, root: *@This().Node) !*@This() {
            var tree = try allocator.create(@This());
            tree.root = root;

            return tree;
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            self.root.deinit_tree(allocator);
            allocator.destroy(self);
        }

        pub fn print(self: @This(), allocator: std.mem.Allocator) void {
            var children = self.root.list();
            while (children.next()) |child| {
                child.print(allocator);
            }
        }
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
