const std = @import("std");
const tree_sitter = @import("tree_sitter");
const c = @cImport({
    @cInclude("Python.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

pub export fn example(self: [*c]c.PyObject, args: [*c]c.PyObject) callconv(.c) [*c]c.PyObject {
    _ = self;

    const language = tree_sitter_python();
    defer language.destroy();

    var parser = tree_sitter.Parser.create();
    defer parser.destroy();
    parser.setLanguage(language) catch {};

    const tree = parser.parseString("print('hello world')", null);
    defer {
        if (tree) |confirmed_tree| {
            confirmed_tree.destroy();
        }
    }

    std.debug.print("{any}\n", .{tree});

    var value: c_long = undefined;
    _ = c.PyArg_ParseTuple(args, "l", &value);

    return c.PyLong_FromLong(value + 1);
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

pub export var spam_module = c.PyModuleDef{
    .m_methods = &spam_methods,
};

pub export fn PyInit_spam() callconv(.c) [*c]c.PyObject {
    return c.PyModuleDef_Init(&spam_module);
}
