const Client = okredis.Client;
const U8PathTree = path_tree.U8PathTree;
const debug = std.debug;
const net = std.net;
const okredis = @import("./okredis/okredis.zig");
const path_tree = @import("./path_tree.zig");
const std = @import("std");
const spoon = @import("./zig-spoon/import.zig");
const os = std.os;

const Renderer = struct {
    const render_start = 2;
    term: spoon.Term = undefined,
    cursor_line: usize = 0,
    selection_height: usize = 80,
    top_node: *U8PathTree.Node = null,
    render_end: usize = 0,
    fds: [1]os.pollfd = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *@This(), allocator: std.mem.Allocator, top_node: *U8PathTree.Node) !void {
        self.allocator = allocator;
        self.top_node = top_node;
        try self.term.init();

        self.fds[0] = .{
            .fd = self.term.tty.handle,
            .events = os.POLL.IN,
            .revents = undefined,
        };

        try self.term.uncook(.{});
    }

    pub fn deinit(self: *@This()) !void {
        try self.term.cook();
        self.term.deinit();
    }

    pub fn resize(self: *@This()) !void {
        try self.term.fetchSize();
        self.selection_height = self.term.height - 2;
        try self.term.setWindowTitle("Redis Explorer", .{});
        try self.render_alloc();
    }

    fn render_header(self: *@This(), allocator: std.mem.Allocator, rc: *spoon.Term.RenderContext) !void {
        try rc.moveCursorTo(0, 0);
        try rc.setAttribute(.{ .fg = .green, .reverse = true });

        var rpw = rc.restrictedPaddingWriter(self.term.width);
        try rpw.writer().writeAll("Redis Explorer ~ Use arrow keys to navigate or ? for help");
        try rpw.pad();

        try rc.moveCursorTo(1, 0);
        try rc.setAttribute(.{ .fg = .cyan, .reverse = true });

        rpw = rc.restrictedPaddingWriter(self.term.width);
        if (self.top_node.parent) |parent| {
            var path = try parent.path(allocator, 64);
            defer allocator.free(path);
            try rpw.writer().writeAll(path);
        }
        try rpw.pad();
    }

    fn render_footer(self: *@This(), rc: *spoon.Term.RenderContext) !void {
        try rc.moveCursorTo(self.term.height - 1, 0);
        try rc.setAttribute(.{ .fg = .green, .reverse = true });

        var rpw = rc.restrictedPaddingWriter(self.term.width);
        try rpw.writer().writeAll("Footer");
        try rpw.pad();
    }

    fn render_no_keys(self: *@This(), rc: *spoon.Term.RenderContext) !void {
        try rc.moveCursorTo(self.term.height / 2, 0);
        try rc.setAttribute(.{ .fg = .red, .reverse = true });

        var rpw = rc.restrictedPaddingWriter(self.term.width);
        try rpw.writer().writeAll("No records to show");
        try rpw.pad();
    }

    fn render_node(
        self: *@This(),
        rc: *spoon.Term.RenderContext,
        node: *U8PathTree.Node,
        is_selected: bool,
    ) !void {
        var attr = spoon.Attribute{};

        if (is_selected) {
            attr.reverse = true;
        }
        if (node.first_child) |_| {
            attr.fg = .blue;
            attr.bold = true;
        }

        try rc.setAttribute(attr);

        var rpw = rc.restrictedPaddingWriter(self.term.width);
        try rpw.writer().writeAll(node.data);

        if (is_selected) {
            try rpw.pad();
        }
    }

    fn render_nodes(self: *@This(), rc: *spoon.Term.RenderContext) !void {
        var i: usize = 0;
        var iter = self.top_node.iter();
        while (i < self.selection_height - 1) : (i += 1) {
            try rc.moveCursorTo(render_start + i, 0);

            if (iter.next()) |n| {
                try self.render_node(rc, n, i == self.cursor_line);
            } else {
                break;
            }
        }
        self.render_end = i;
    }

    pub fn render(self: *@This(), allocator: std.mem.Allocator) !void {
        var rc = try self.term.getRenderContext();
        defer rc.done() catch {};

        try rc.clear();

        try self.render_header(allocator, &rc);
        try self.render_footer(&rc);
        try self.render_nodes(&rc);
    }

    pub fn render_alloc(self: *@This()) !void {
        try self.render(self.allocator);
    }

    fn handle_arrow_down(self: *@This()) void {
        if (self.cursor_line < self.render_end - 1) {
            self.cursor_line += 1;
        } else {
            self.top_node = self.top_node.siblings_right(1);
        }
    }

    fn handle_arrow_up(self: *@This()) void {
        if (self.cursor_line > 0) {
            self.cursor_line -= 1;
        } else {
            self.top_node = self.top_node.siblings_left(1);
        }
    }

    fn handle_page_down(self: *@This()) void {
        self.top_node = self.top_node.siblings_right(self.selection_height - 1);
    }

    fn handle_page_up(self: *@This()) void {
        self.top_node = self.top_node.siblings_left(self.selection_height - 1);
    }

    fn handle_arrow_right(self: *@This()) void {
        var i: usize = 0;
        var current_node: ?*U8PathTree.Node = self.top_node;

        while (current_node) |n| {
            if (i == self.cursor_line) {
                if (n.first_child) |nc| {
                    self.top_node = nc;
                }
                self.cursor_line = 0;
                break;
            }

            if (n.next_sibling) |ns| {
                current_node = ns;
            } else {
                break;
            }

            i += 1;
        }
    }

    fn handle_arrow_left(self: *@This()) void {
        if (self.top_node.parent) |parent| {
            self.top_node = parent;
            self.cursor_line = 0;
        }
    }

    pub fn render_loop_alloc(self: *@This()) !void {
        try self.resize();

        var buf: [16]u8 = undefined;
        while (true) {
            _ = try os.poll(&self.fds, -1);

            const read = try self.term.readInput(&buf);
            var it = spoon.inputParser(buf[0..read]);

            while (it.next()) |in| {
                if (in.eqlDescription("escape") or in.eqlDescription("q")) {
                    return;
                }

                if (in.eqlDescription("arrow-down") or in.eqlDescription("j")) {
                    self.handle_arrow_down();
                } else if (in.eqlDescription("arrow-up") or in.eqlDescription("k")) {
                    self.handle_arrow_up();
                } else if (in.eqlDescription("arrow-right")) {
                    self.handle_arrow_right();
                } else if (in.eqlDescription("arrow-left")) {
                    self.handle_arrow_left();
                } else if (in.eqlDescription("page-down")) {
                    self.handle_page_down();
                } else if (in.eqlDescription("page-up")) {
                    self.handle_page_up();
                }

                try self.render_alloc();
            }
        }
    }
};

var renderer: Renderer = undefined;

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

    var tree = U8PathTree.init();
    defer tree.deinit(allocator);

    for (keys) |key| {
        _ = try tree.insert_path(allocator, key, ":");
    }

    if (tree.root) |root| {
        try renderer.init(allocator, root);
    } else {
        std.debug.print("Error: Keys is empty. Exiting.\n", .{});
    }
    defer renderer.deinit() catch {};

    os.sigaction(os.SIG.WINCH, &os.Sigaction{
        .handler = .{ .handler = handleSigWinch },
        .mask = os.empty_sigset,
        .flags = 0,
    }, null);

    try renderer.render_loop_alloc();
}

pub fn handleSigWinch(_: c_int) callconv(.C) void {
    renderer.resize() catch {};
}

/// as otherwise all messages will be mangled.
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    renderer.term.cook() catch {};
    std.builtin.default_panic(msg, trace);
}
