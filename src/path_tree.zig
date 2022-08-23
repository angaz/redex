const std = @import("std");

pub fn PathTree(comptime T: type, comptime order: fn (T, T) std.math.Order) type {
    return struct {
        pub const Node = struct {
            first_child: ?*@This() = null,
            next_sibling: ?*@This() = null,

            parent: ?*@This() = null,
            previous_sibling: ?*@This() = null,

            data: T,

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

            pub fn print(self: *@This()) void {
                std.debug.print("{s}\n", .{self.data});
                var children = self.list();
                while (children.next()) |child| {
                    child.print();
                }
            }
        };

        root: *@This().Node,

        pub fn init(allocator: std.mem.Allocator, root: *@This().Node) !*@This() {
            var tree = try allocator.create(@This());
            tree.root = root;

            return tree;
        }

        pub fn print(self: @This()) void {
            var children = self.root.list();
            while (children.next()) |child| {
                child.print();
            }
        }
    };
}
