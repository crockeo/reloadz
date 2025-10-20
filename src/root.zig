const std = @import("std");
const tree_sitter = @import("tree_sitter");
const c = @cImport({
    @cInclude("Python.h");
    @cInclude("string.h");
});

const hot_reloader = @import("./hot_reloader.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const default_allocator = gpa.allocator();

var hot_reloader_methods = [_]c.PyMethodDef{
    c.PyMethodDef{
        .ml_doc = null,
        .ml_flags = c.METH_VARARGS,
        .ml_meth = &hot_reloader_file_changed,
        .ml_name = "file_changed",
    },
    c.PyMethodDef{
        .ml_doc = null,
        .ml_flags = c.METH_VARARGS,
        .ml_meth = &hot_reloader_parse_file,
        .ml_name = "parse_file",
    },
    c.PyMethodDef{ .ml_doc = null, .ml_flags = 0, .ml_meth = null, .ml_name = null },
};

var hot_reloader_type = c.PyTypeObject{
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
    .tp_basicsize = @sizeOf(hot_reloader.HotReloader),
    .tp_doc = c.PyDoc_STR("Hot reloading system for Python."),
    .tp_flags = c.Py_TPFLAGS_DEFAULT,
    .tp_free = hot_reloader_free,
    .tp_init = hot_reloader_init,
    .tp_itemsize = 0,
    .tp_methods = &hot_reloader_methods,
    .tp_name = "reloadz.HotReloader",
    .tp_new = c.PyType_GenericNew,
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

fn hot_reloader_file_changed(
    self_raw: [*c]c.PyObject,
    args: [*c]c.PyObject,
) callconv(.c) [*c]c.PyObject {
    var path_raw: [*c]u8 = undefined;
    if (c.PyArg_ParseTuple(args, "s", &path_raw) == 0) {
        c.PyErr_SetString(c.PyExc_TypeError, "Must call with exactly 1 string arg.");
        return null;
    }
    const path = path_raw[0..c.strlen(path_raw)];

    const self: *hot_reloader.HotReloader = @ptrCast(self_raw.?);
    self.file_changed(path) catch {
        c.PyErr_SetString(c.PyExc_Exception, "Unexpected error while parsing.");
        return null;
    };

    return c.Py_None();
}

fn hot_reloader_parse_file(
    self_raw: [*c]c.PyObject,
    args: [*c]c.PyObject,
) callconv(.c) [*c]c.PyObject {
    var path_raw: [*c]u8 = undefined;
    if (c.PyArg_ParseTuple(args, "s", &path_raw) == 0) {
        c.PyErr_SetString(c.PyExc_TypeError, "Must call with exactly 1 string arg.");
        return null;
    }
    const path = path_raw[0..c.strlen(path_raw)];

    const self: *hot_reloader.HotReloader = @ptrCast(self_raw.?);
    self.parse_file(path) catch {
        c.PyErr_SetString(c.PyExc_Exception, "Unexpected error while parsing.");
        return null;
    };

    return c.Py_None();
}

fn init(module: [*c]c.PyObject) callconv(.c) c_int {
    if (c.PyType_Ready(&hot_reloader_type) < 0) {
        return -1;
    }
    if (c.PyModule_AddObjectRef(module, "HotReloader", @ptrCast(&hot_reloader_type)) < 0) {
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

var reloadz_module = c.PyModuleDef{
    .m_free = deinit,
    .m_name = "reloadz",
    .m_slots = &reloadz_module_slots,
};

pub export fn PyInit_reloadz() callconv(.c) [*c]c.PyObject {
    return c.PyModuleDef_Init(&reloadz_module);
}
