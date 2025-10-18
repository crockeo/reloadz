const std = @import("std");
const c = @cImport({
    @cInclude("Python.h");
});

pub export fn example(self: [*c]c.PyObject, args: [*c]c.PyObject) callconv(.c) [*c]c.PyObject {
    _ = self;

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
