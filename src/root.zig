const std = @import("std");
const tree_sitter = @import("tree_sitter");
const c = @cImport({
    @cInclude("Python.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const default_allocator = gpa.allocator();

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

pub export fn example(self: [*c]c.PyObject, args: [*c]c.PyObject) callconv(.c) [*c]c.PyObject {
    _ = self;

    const language = tree_sitter_python();
    defer language.destroy();

    var parser = tree_sitter.Parser.create();
    defer parser.destroy();
    parser.setLanguage(language) catch {
        c.PyErr_SetString(c.PyExc_Exception, "Unable to set parser.");
        return null;
    };

    const tree = parser.parseString("print('hello world')", null) orelse {
        c.PyErr_SetString(c.PyExc_Exception, "Unable to parse tree.");
        return null;
    };
    defer tree.destroy();

    walk_tree(default_allocator, tree) catch {
        c.PyErr_SetString(c.PyExc_Exception, "Unable to walk tree.");
        return null;
    };

    var value: c_long = undefined;
    _ = c.PyArg_ParseTuple(args, "l", &value);

    return c.PyLong_FromLong(value + 1);
}

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

pub export var spam_methods = [_]c.PyMethodDef{
    c.PyMethodDef{
        .ml_doc = null,
        .ml_flags = c.METH_VARARGS,
        .ml_meth = &example,
        .ml_name = "example",
    },
    c.PyMethodDef{ .ml_doc = null, .ml_flags = 0, .ml_meth = null, .ml_name = null },
};

fn deinit(_: ?*anyopaque) callconv(.c) void {
    _ = gpa.deinit();
}

pub export var spam_module = c.PyModuleDef{
    .m_methods = &spam_methods,
    .m_free = deinit,
};

pub export fn PyInit_spam() callconv(.c) [*c]c.PyObject {
    return c.PyModuleDef_Init(&spam_module);
}
