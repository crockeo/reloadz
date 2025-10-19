const std = @import("std");
const tree_sitter = @import("tree_sitter");

const c = @cImport({
    @cInclude("Python.h");
});

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

pub const HotReloader = struct {
    const Self = @This();

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
};
