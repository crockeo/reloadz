const std = @import("std");
const tree_sitter = @import("tree_sitter");

const c = @cImport({
    @cInclude("Python.h");
});

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

const HotReloaderError = error{
    FailedParse,
};

pub const HotReloader = struct {
    const Self = @This();

    // This is required as the first object,
    // so that we have a memory region reserved for it.
    ob_base: c.PyObject,

    allocator: std.mem.Allocator,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    language: *tree_sitter.Language,
    parser: *tree_sitter.Parser,

    pub fn init(self: *Self) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};
        self.allocator = self.gpa.allocator();

        const language = tree_sitter_python();
        errdefer language.destroy();

        var parser = tree_sitter.Parser.create();
        errdefer parser.destroy();
        try parser.setLanguage(language);

        self.language = language;
        self.parser = parser;
    }

    pub fn deinit(self: *Self) void {
        self.language.destroy();
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
