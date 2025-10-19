const std = @import("std");
const tree_sitter = @import("tree_sitter");
const c = @cImport({
    @cInclude("Python.h");
});

const hot_reloader = @import("./hot_reloader.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const default_allocator = gpa.allocator();

// pub export fn example(self: [*c]c.PyObject, args: [*c]c.PyObject) callconv(.c) [*c]c.PyObject {
//     _ = self;
//
//
//     var parser = tree_sitter.Parser.create();
//     defer parser.destroy();
//     parser.setLanguage(language) catch {
//         c.PyErr_SetString(c.PyExc_Exception, "Unable to set parser.");
//         return null;
//     };
//
//     const tree = parser.parseString("print('hello world')", null) orelse {
//         c.PyErr_SetString(c.PyExc_Exception, "Unable to parse tree.");
//         return null;
//     };
//     defer tree.destroy();
//
//     walk_tree(default_allocator, tree) catch {
//         c.PyErr_SetString(c.PyExc_Exception, "Unable to walk tree.");
//         return null;
//     };
//
//     var value: c_long = undefined;
//     _ = c.PyArg_ParseTuple(args, "l", &value);
//
//     return c.PyLong_FromLong(value + 1);
// }
//
// fn walk_tree(allocator: std.mem.Allocator, tree: *const tree_sitter.Tree) !void {
//     var stack = std.ArrayList(tree_sitter.Node).empty;
//     defer stack.deinit(allocator);
//
//     try stack.append(allocator, tree.rootNode());
//     while (stack.pop()) |node| {
//         std.debug.print("{s}\n", .{node.kind()});
//
//         var cursor = node.walk();
//         if (!cursor.gotoFirstChild()) {
//             continue;
//         }
//         try stack.append(allocator, cursor.node());
//         while (cursor.gotoNextSibling()) {
//             try stack.append(allocator, cursor.node());
//         }
//     }
// }

var HotReloaderType = c.PyTypeObject{
    // We do not have access to `PyVarObject_HEAD_INIT` in Zig,
    // because the Zig compiler cannot parse the `define`.
    // Instead we populate `.ob_base` manually.
    .ob_base = .{
        .ob_base = .{
            .unnamed_0 = .{ .ob_refcnt = c._Py_IMMORTAL_REFCNT },
            .ob_type = null,
        },
        .ob_size = 0,
    },
    .tp_name = "reloadz.HotReloader",
    .tp_doc = c.PyDoc_STR("Hot reloading system for Python."),
    .tp_basicsize = @sizeOf(hot_reloader.HotReloader),
    .tp_itemsize = 0,
    .tp_flags = c.Py_TPFLAGS_DEFAULT,
    .tp_new = c.PyType_GenericNew,
    .tp_init = hot_reloader_init,
    .tp_free = hot_reloader_free,
};

fn hot_reloader_init(
    self_raw: [*c]c.PyObject,
    _: [*c]c.PyObject,
    _: [*c]c.PyObject,
) callconv(.c) c_int {
    var self: *hot_reloader.HotReloader = @ptrCast(self_raw.?);
    self.init() catch {
        // TODO: exception type
        c.PyErr_SetString(c.PyExc_Exception, "Failed to initialize hot reloader");
        return -1;
    };
    return 0;
}

fn hot_reloader_free(self_raw: ?*anyopaque) callconv(.c) void {
    var self: *hot_reloader.HotReloader = @ptrCast(@alignCast(self_raw.?));
    self.deinit();
}

fn hot_reloader_parse(self_raw: [*c]c.PyObject, _: [*c]c.PyObject, _: [*c]c.PyObject) void {
    const self: *hot_reloader.HotReloader = @ptrCast(self_raw.?);
    _ = self;
}

fn init(module: [*c]c.PyObject) callconv(.c) c_int {
    if (c.PyType_Ready(&HotReloaderType) < 0) {
        return -1;
    }
    if (c.PyModule_AddObjectRef(module, "HotReloader", @ptrCast(&HotReloaderType)) < 0) {
        return -1;
    }
    return 0;
}

fn deinit(_: ?*anyopaque) callconv(.c) void {
    _ = gpa.deinit();
}

var reloadz_module_slots = [_]c.PyModuleDef_Slot{
    c.PyModuleDef_Slot{ .slot = c.Py_mod_exec, .value = @ptrCast(@constCast(&init)) },
    c.PyModuleDef_Slot{ .slot = 0, .value = null },
};

var reloadz_methods = [_]c.PyMethodDef{
    // c.PyMethodDef{
    //     .ml_doc = null,
    //     .ml_flags = c.METH_VARARGS,
    //     .ml_meth = &example,
    //     .ml_name = "example",
    // },
    c.PyMethodDef{ .ml_doc = null, .ml_flags = 0, .ml_meth = null, .ml_name = null },
};

var reloadz_module = c.PyModuleDef{
    .m_free = deinit,
    .m_methods = &reloadz_methods,
    .m_name = "reloadz",
    .m_slots = &reloadz_module_slots,
};

pub export fn PyInit_reloadz() callconv(.c) [*c]c.PyObject {
    return c.PyModuleDef_Init(&reloadz_module);
}
