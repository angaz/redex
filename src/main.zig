const std = @import("std");
const path_tree = @import("./path_tree.zig");
const net = std.net;
const okredis = @import("./zig-okredis/src/okredis.zig");
const Client = okredis.Client;
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

fn u8_order(left: []const u8, right: []const u8) std.math.Order {
    return std.mem.order(u8, left, right);
}
const KeyTree = path_tree.PathTree([]const u8, u8_order);

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

    var root = try KeyTree.Node.init(allocator, "/root/");
    var tree = try KeyTree.init(allocator, root);

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
