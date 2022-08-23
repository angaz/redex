const std = @import("std");
const path_tree = @import("./path_tree.zig");
const U8PathTree = path_tree.U8PathTree;
const net = std.net;
const okredis = @import("./zig-okredis/src/okredis.zig");
const Client = okredis.Client;
const debug = std.debug;

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

    var root = try U8PathTree.Node.init(allocator, "/root/");
    var tree = try U8PathTree.init(allocator, root);
    defer tree.deinit(allocator);

    for (keys) |key| {
        var it = std.mem.split(u8, key, ":");

        var current_node = tree.root;
        while (it.next()) |name| {
            var n = try U8PathTree.Node.init(allocator, name);
            current_node = current_node.insert_child(n);
        }
    }

    tree.print();
}
