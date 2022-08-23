const std = @import("std");
const net = std.net;
const okredis = @import("./zig-okredis/src/okredis.zig");
const Client = okredis.Client;
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

const KeyTree = struct {
    pub const Node = struct {
        first_child: ?*Node = null,
        next_sibling: ?*Node = null,

        parent: ?*Node = null,
        previous_sibling: ?*Node = null,

        data: []const u8,

        pub fn insert_child(self: *@This(), n: *Node) *Node {
            if (self.first_child) |first_child| {
                var cmp = std.mem.order(u8, n.data, first_child.data);

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
                    cmp = std.mem.order(u8, n.data, next_sibling.data);

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

        pub fn init(allocator: std.mem.Allocator, data: []const u8) !*Node {
            var n = try allocator.create(Node);
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

        pub fn print(self: *@This()) void {
            std.debug.print("{s}\n", .{self.data});
            var children = self.list();
            while (children.next()) |child| {
                child.print();
            }
        }
    };

    root: *Node,

    pub fn init(allocator: std.mem.Allocator) !*KeyTree {
        var tree = try allocator.create(KeyTree);
        tree.root = try KeyTree.Node.init(allocator, "/root/");

        return tree;
    }

    pub fn print(self: @This()) void {
        var children = self.root.list();
        while (children.next()) |child| {
            child.print();
        }
    }
};

test "key tree" {
    var rn = KeyTree.Node{ .data = "/root/" };
    var kt = KeyTree{ .root = &rn };

    try testing.expect(std.mem.eql(u8, kt.root.data, "/root/"));
    var cn = kt.root;
    var n = KeyTree.Node{ .data = "movies" };
    _ = cn.insert_child(&n);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "movies"));
    var n2 = KeyTree.Node{ .data = "actors" };
    _ = cn.insert_child(&n2);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "movies"));
    var n3 = KeyTree.Node{ .data = "directors" };
    _ = cn.insert_child(&n3);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    var n4 = KeyTree.Node{ .data = "vfx" };
    _ = cn.insert_child(&n3);
    _ = cn.insert_child(&n4);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.next_sibling.?.data, "vfx"));

    var n5 = KeyTree.Node{ .data = "12345" };
    _ = n2.insert_child(&n5);
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.data, "actors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.data, "directors"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.data, "movies"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.next_sibling.?.next_sibling.?.next_sibling.?.data, "vfx"));
    try testing.expect(std.mem.eql(u8, kt.root.first_child.?.first_child.?.data, "12345"));
}

pub fn main() !void {
    const addr = try net.Address.parseIp4("0.0.0.0", 6379);
    var connection = try net.tcpConnectToAddress(addr);

    var client: Client = undefined;
    try client.init(connection);
    defer client.close();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    //defer {
    //    const leaked = gpa.deinit();
    //    if (leaked) {
    //        std.debug.print("Memory was leaked\n", .{});
    //    }
    //}

    var keys = try client.sendAlloc([][]u8, allocator, .{ "KEYS", "*" });
    defer allocator.free(keys);

    var tree = try KeyTree.init(allocator);

    for (keys) |key| {
        var it = std.mem.split(u8, key, ":");

        var current_node = tree.root;
        while (it.next()) |name| {
            var n = try KeyTree.Node.init(allocator, name);
            current_node = current_node.insert_child(n);
        }
    }

    tree.print();
}
