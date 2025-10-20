const std = @import("std");
const tree_sitter = @import("tree_sitter");

const c = @cImport({
    @cInclude("Python.h");
});

const import_graph = @import("import_graph.zig");

extern fn tree_sitter_python() callconv(.c) *tree_sitter.Language;

const HotReloaderError = error{
    FailedParse,
    OutOfMemory,
    Unsupported,
};

const NS_DEBOUNCE_PERIOD = 250 * std.time.ns_per_ms;

pub const HotReloader = struct {
    const Self = @This();

    // This is required as the first object,
    // so that we have a memory region reserved for it.
    ob_base: c.PyObject,

    allocator: std.mem.Allocator,
    background_thread: std.Thread,
    condvar: std.Thread.Condition,
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    import_graph: import_graph.ImportGraph,
    language: *tree_sitter.Language,
    last_file_change: std.time.Instant,
    mutex: std.Thread.Mutex,
    parser: *tree_sitter.Parser,
    pending_reloads: std.StringHashMap(struct {}),

    pub fn init(self: *Self) !void {
        self.gpa = std.heap.GeneralPurposeAllocator(.{}){};

        const language = tree_sitter_python();
        errdefer language.destroy();

        var parser = tree_sitter.Parser.create();
        errdefer parser.destroy();
        try parser.setLanguage(language);

        self.allocator = self.gpa.allocator();
        self.condvar = .{};
        self.import_graph = import_graph.ImportGraph.init(self.allocator, parser);
        self.language = language;
        self.last_file_change = try .now();
        self.mutex = .{};
        self.parser = parser;
        self.pending_reloads = .init(self.allocator);

        // This has to be initialized after everything else,
        // so that everything is set before the background thread is started.
        self.background_thread = try .spawn(
            .{
                .allocator = self.allocator,
            },
            Self.background_thread_main,
            .{self},
        );
    }

    pub fn deinit(self: *Self) void {
        self.import_graph.deinit();
        self.language.destroy();
        self.parser.destroy();

        var iter = self.pending_reloads.keyIterator();
        while (iter.next()) |path| {
            self.allocator.free(path.*);
        }
        self.pending_reloads.deinit();
    }

    pub fn file_changed(self: *Self, path: []const u8) HotReloaderError!void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.pending_reloads.put(try self.allocator.dupe(u8, path), .{});
        self.last_file_change = try std.time.Instant.now();
        self.condvar.signal();
    }

    fn background_thread_main(self: *Self) HotReloaderError!void {
        while (true) {
            self.mutex.lock();

            const now = try std.time.Instant.now();
            const ns_since_last_change = now.since(self.last_file_change);
            if (ns_since_last_change < NS_DEBOUNCE_PERIOD) {
                self.mutex.unlock();
                std.Thread.sleep(NS_DEBOUNCE_PERIOD - ns_since_last_change);
                continue;
            }

            if (self.pending_reloads.count() > 0) {
                self.handle_pending_reloads();
                self.mutex.unlock();
                continue;
            }

            self.condvar.wait(&self.mutex);
        }
    }

    fn handle_pending_reloads(self: *Self) void {
        if (self.pending_reloads.count() == 0) {
            @panic("Logic error. Should only be called when we have pending reloads.");
        }

        var iter = self.pending_reloads.keyIterator();
        while (iter.next()) |path| {
            self.import_graph.parse_file(path.*) catch {};
        }
        self.clear_pending_reloads();
    }

    fn clear_pending_reloads(self: *Self) void {
        var iter = self.pending_reloads.keyIterator();
        while (iter.next()) |path| {
            self.allocator.free(path.*);
        }
        self.pending_reloads.clearAndFree();
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
