const std = @import("std");
const tree_sitter = @import("tree_sitter");

const StringInterner = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    container: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .container = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.container.keyIterator();
        while (iter.next()) |string| {
            self.allocator.free(string.*);
        }
        self.container.deinit();
    }

    pub fn add_string(self: *Self, string: []const u8) error{OutOfMemory}![]const u8 {
        if (self.container.get(string)) |existing_string| {
            return existing_string;
        }
        const string_dupe = self.allocator.dupe(u8, string);
        try self.container.put(string_dupe, string_dupe);
        return string_dupe;
    }
};

const StringSet = std.StringHashMap(struct {});
const ImportGraphContainer = std.StringHashMap(std.StringHashMap(StringSet));

pub const ImportGraph = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    import_graph: ImportGraphContainer,
    interner: StringInterner,
    parser: *tree_sitter.Parser,

    pub fn init(allocator: std.mem.Allocator, parser: *tree_sitter.Parser) Self {
        return .{
            .allocator = allocator,
            .import_graph = .init(allocator),
            .interner = .init(allocator),
            .parser = parser,
        };
    }

    pub fn deinit(self: *Self) void {
        self.import_graph.deinit();
        self.interner.deinit();
    }

    pub fn modules(self: *const Self) ImportGraphContainer.KeyIterator {
        return self.import_graph.keyIterator();
    }

    pub fn neighbors(self: *const Self, module_name: []const u8) ?StringSet.KeyIterator {
        const module_set = self.import_graph.get(module_name) orelse return null;
        return module_set.keyIterator();
    }

    pub fn parse_file(self: *Self, path: []const u8) !void {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        const file_input = try self.allocator.create(FileInput);
        file_input.* = .{
            .buffer = &buffer,
            .file = &file,
            .err = null,
        };
        defer self.allocator.destroy(file_input);

        const tree = self.parser.parse(.{
            .encoding = .utf8,
            .payload = @ptrCast(file_input),
            .read = ts_input_from_file,
        }, null) orelse {
            if (file_input.err) |err| {
                return err;
            }
            return error.FailedToParse;
        };
        defer tree.destroy();

        if (file_input.err) |err| {
            return err;
        }
    }
};

const FileInput = struct {
    buffer: []u8,
    file: *std.fs.File,
    err: ?(std.fs.File.SeekError || std.fs.File.ReadError),
};

fn ts_input_from_file(
    payload: ?*anyopaque,
    byte_index: u32,
    _: tree_sitter.Point,
    bytes_read: *u32,
) callconv(.c) [*c]const u8 {
    var file_input: *FileInput = @ptrCast(@alignCast(payload));
    file_input.file.seekTo(byte_index) catch |err| {
        file_input.err = err;
        bytes_read.* = 0;
        return null;
    };
    const bytes_read_usize = file_input.file.read(file_input.buffer) catch |err| {
        file_input.err = err;
        bytes_read.* = 0;
        return null;
    };
    if (bytes_read_usize == 0) {
        bytes_read.* = 0;
        return null;
    }

    bytes_read.* = @intCast(bytes_read_usize);
    return file_input.buffer.ptr;
}
