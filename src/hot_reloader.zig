const std = @import("std");
const tree_sitter = @import("tree_sitter");

const c = @cImport({
    @cInclude("Python.h");
});

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

const HotReloaderError = error{
    FailedParse,
    OutOfMemory,
    Unsupported,
};

pub const HotReloader = struct {
    const Self = @This();

    // This is required as the first object,
    // so that we have a memory region reserved for it.
    ob_base: c.PyObject,

    allocator: std.mem.Allocator,
    condvar: std.Thread.Condition,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    language: *tree_sitter.Language,
    last_file_change: std.time.Instant,
    mutex: std.Thread.Mutex,
    parser: *tree_sitter.Parser,
    pending_reloads: std.ArrayList([]const u8),

    pub fn init(self: *Self) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};

        const language = tree_sitter_python();
        errdefer language.destroy();

        var parser = tree_sitter.Parser.create();
        errdefer parser.destroy();
        try parser.setLanguage(language);

        self.allocator = self.gpa.allocator();
        self.condvar = .{};
        self.language = language;
        self.last_file_change = try .now();
        self.mutex = .{};
        self.parser = parser;
        self.pending_reloads = .empty;
    }

    pub fn deinit(self: *Self) void {
        self.language.destroy();
        self.parser.destroy();
    }

    pub fn file_changed(self: *Self, path: []const u8) HotReloaderError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.pending_reloads.append(self.allocator, try self.allocator.dupe(path));
        self.last_file_change = try std.time.Instant.now();
        self.condvar.signal();
    }

    pub fn parse_file(self: *const Self, path: []const u8) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(self.allocator, std.math.maxInt(usize));
        defer self.allocator.free(contents);

        const tree = self.parser.parseString(contents, null) orelse {
            return HotReloaderError.FailedParse;
        };
        defer tree.destroy();

        try walk_tree(self.allocator, tree);
    }
};

fn walk_tree(allocator: std.mem.Allocator, tree: *const tree_sitter.Tree) !void {
    var stack = std.ArrayList(tree_sitter.Node).empty;
    defer stack.deinit(allocator);

    try stack.append(allocator, tree.rootNode());
    while (stack.pop()) |node| {
        std.debug.print("{s}\n", .{node.kind()});

        var cursor = node.walk();
        if (!cursor.gotoFirstChild()) {
            continue;
        }
        try stack.append(allocator, cursor.node());
        while (cursor.gotoNextSibling()) {
            try stack.append(allocator, cursor.node());
        }
    }
}
