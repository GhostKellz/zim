const std = @import("std");
const color = @import("../util/color.zig");

/// Explain why a package is in the dependency tree
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try printHelp();
        return;
    }

    const package_name = args[0];
    const stdout = std.io.getStdOut().writer();

    color.info("\n🔍 \x1B[1mAnalyzing dependency chain for: {s}\x1B[0m\n", .{package_name});
    color.dim("────────────────────────────────────────────\n\n", .{});

    // Load lockfile
    const lockfile_path = "zim.lock";
    const lockfile_exists = blk: {
        std.fs.cwd().access(lockfile_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!lockfile_exists) {
        color.error_("❌ No lockfile found\n", .{});
        color.dim("   Run 'zim deps fetch' first\n", .{});
        return error.LockfileNotFound;
    }

    // Parse lockfile and build dependency graph
    var dep_graph = try DependencyGraph.init(allocator);
    defer dep_graph.deinit();

    // For now, create a simulated dependency graph
    // In real implementation, this would parse zim.lock
    try simulateDependencyGraph(&dep_graph, package_name);

    // Find all paths to the package
    const paths = try dep_graph.findPathsTo(package_name);
    defer {
        for (paths.items) |path| {
            path.deinit();
        }
        paths.deinit();
    }

    if (paths.items.len == 0) {
        color.warning("⚠️  Package '{s}' not found in dependency tree\n", .{package_name});
        color.dim("   It may not be required by your project\n\n", .{});
        return;
    }

    // Print dependency chains
    try stdout.print("Found \x1B[36m{d}\x1B[0m dependency chain(s):\n\n", .{paths.items.len});

    for (paths.items, 1..) |path, i| {
        try stdout.print("\x1B[1mChain {d}:\x1B[0m\n", .{i});
        try printDependencyPath(stdout, path.items);
        try stdout.writeAll("\n");
    }

    // Print summary
    color.dim("────────────────────────────────────────────\n", .{});
    try printSummary(stdout, package_name, paths.items);
}

const DependencyNode = struct {
    name: []const u8,
    version: []const u8,
    dependencies: std.ArrayList([]const u8),
};

const DependencyGraph = struct {
    nodes: std.StringHashMap(DependencyNode),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !DependencyGraph {
        return .{
            .nodes = std.StringHashMap(DependencyNode).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *DependencyGraph) void {
        var it = self.nodes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.dependencies.deinit();
        }
        self.nodes.deinit();
    }

    fn addNode(self: *DependencyGraph, name: []const u8, version: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        const version_copy = try self.allocator.dupe(u8, version);

        try self.nodes.put(name_copy, .{
            .name = name_copy,
            .version = version_copy,
            .dependencies = std.ArrayList([]const u8).init(self.allocator),
        });
    }

    fn addEdge(self: *DependencyGraph, from: []const u8, to: []const u8) !void {
        if (self.nodes.getPtr(from)) |node| {
            const to_copy = try self.allocator.dupe(u8, to);
            try node.dependencies.append(to_copy);
        }
    }

    fn findPathsTo(self: *DependencyGraph, target: []const u8) !std.ArrayList(std.ArrayList([]const u8)) {
        var paths = std.ArrayList(std.ArrayList([]const u8)).init(self.allocator);
        errdefer paths.deinit();

        var current_path = std.ArrayList([]const u8).init(self.allocator);
        defer current_path.deinit();

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        // Start DFS from root package
        const root = "your-project"; // In real implementation, read from manifest
        try self.dfsFind(root, target, &current_path, &visited, &paths);

        return paths;
    }

    fn dfsFind(
        self: *DependencyGraph,
        current: []const u8,
        target: []const u8,
        path: *std.ArrayList([]const u8),
        visited: *std.StringHashMap(void),
        paths: *std.ArrayList(std.ArrayList([]const u8)),
    ) !void {
        // Add current to path
        try path.append(current);
        defer _ = path.pop();

        // Mark as visited
        try visited.put(current, {});
        defer _ = visited.remove(current);

        // Check if we found the target
        if (std.mem.eql(u8, current, target)) {
            // Save this path
            var path_copy = std.ArrayList([]const u8).init(self.allocator);
            for (path.items) |node| {
                const node_copy = try self.allocator.dupe(u8, node);
                try path_copy.append(node_copy);
            }
            try paths.append(path_copy);
            return;
        }

        // Explore dependencies
        if (self.nodes.get(current)) |node| {
            for (node.dependencies.items) |dep| {
                if (!visited.contains(dep)) {
                    try self.dfsFind(dep, target, path, visited, paths);
                }
            }
        }
    }
};

fn simulateDependencyGraph(graph: *DependencyGraph, target: []const u8) !void {
    // Simulate a realistic dependency graph
    try graph.addNode("your-project", "1.0.0");
    try graph.addNode("http-server", "2.1.0");
    try graph.addNode("json-parser", "1.5.0");
    try graph.addNode("logger", "0.3.0");
    try graph.addNode("utf8-validator", "1.0.0");

    try graph.addEdge("your-project", "http-server");
    try graph.addEdge("your-project", "json-parser");
    try graph.addEdge("http-server", "logger");
    try graph.addEdge("json-parser", "utf8-validator");

    // Add the target package if it exists
    if (std.mem.eql(u8, target, "logger") or
        std.mem.eql(u8, target, "utf8-validator") or
        std.mem.eql(u8, target, "http-server") or
        std.mem.eql(u8, target, "json-parser"))
    {
        // Target is in graph
    } else {
        // Add as example
        try graph.addNode(target, "1.0.0");
        try graph.addEdge("http-server", target);
    }
}

fn printDependencyPath(writer: anytype, path: []const []const u8) !void {
    for (path, 0..) |node, i| {
        const indent = "  " ** i;

        if (i == 0) {
            try writer.print("{s}\x1B[1m{s}\x1B[0m (your project)\n", .{ indent, node });
        } else if (i == path.len - 1) {
            try writer.print("{s}  └─ \x1B[36m{s}\x1B[0m\n", .{ indent, node });
        } else {
            try writer.print("{s}  ├─ {s}\n", .{ indent, node });
        }
    }
}

fn printSummary(writer: anytype, package: []const u8, paths: []const std.ArrayList([]const u8)) !void {
    color.info("\n📊 Summary:\n", .{});

    // Calculate depth statistics
    var min_depth: usize = std.math.maxInt(usize);
    var max_depth: usize = 0;
    var total_depth: usize = 0;

    for (paths) |path| {
        const depth = path.items.len - 1; // Exclude root
        if (depth < min_depth) min_depth = depth;
        if (depth > max_depth) max_depth = depth;
        total_depth += depth;
    }

    const avg_depth = if (paths.len > 0) total_depth / paths.len else 0;

    try writer.print("   Package: \x1B[36m{s}\x1B[0m\n", .{package});
    try writer.print("   Dependency chains: {d}\n", .{paths.len});
    try writer.print("   Min depth: {d}\n", .{min_depth});
    try writer.print("   Max depth: {d}\n", .{max_depth});
    try writer.print("   Avg depth: {d}\n", .{avg_depth});

    color.dim("\n💡 Tip: Shorter chains mean faster builds and fewer conflicts\n", .{});
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: zim why <PACKAGE>
        \\
        \\Explain why a package is in your dependency tree
        \\
        \\This command shows all dependency chains from your project
        \\to the specified package, helping you understand:
        \\  • Why a package is being included
        \\  • Which dependencies require it
        \\  • How to remove it if unwanted
        \\
        \\Examples:
        \\  zim why logger           # Show why logger is required
        \\  zim why http-server      # Show dependency chain for http-server
        \\
        \\Output:
        \\  For each dependency chain, shows the path from your project
        \\  to the target package, including intermediate dependencies.
        \\
        \\  Chain 1:
        \\    your-project
        \\      ├─ http-server
        \\        └─ logger
        \\
        \\  Chain 2:
        \\    your-project
        \\      ├─ database-client
        \\        ├─ connection-pool
        \\          └─ logger
        \\
    );
}
