const std = @import("std");

/// Dependency graph node for visualization
pub const GraphNode = struct {
    name: []const u8,
    version: []const u8,
    children: std.ArrayList(*GraphNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !*GraphNode {
        const node = try allocator.create(GraphNode);
        node.* = .{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .children = std.ArrayList(*GraphNode).init(allocator),
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *GraphNode) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit();
        self.allocator.destroy(self);
    }

    pub fn addChild(self: *GraphNode, child: *GraphNode) !void {
        try self.children.append(child);
    }
};

/// Print dependency tree with beautiful ASCII art
pub fn printTree(root: *GraphNode, writer: anytype) !void {
    try writer.print("{s} @ {s}\n", .{ root.name, root.version });
    try printTreeRecursive(root, writer, "", true);
}

fn printTreeRecursive(
    node: *GraphNode,
    writer: anytype,
    prefix: []const u8,
    _: bool,
) !void {
    for (node.children.items, 0..) |child, i| {
        const is_child_last = i == node.children.items.len - 1;

        // Print the branch
        try writer.print("{s}", .{prefix});
        if (is_child_last) {
            try writer.print("└── ", .{});
        } else {
            try writer.print("├── ", .{});
        }
        try writer.print("{s} @ {s}\n", .{ child.name, child.version });

        // Recurse for children
        if (child.children.items.len > 0) {
            var new_prefix = std.ArrayList(u8).init(node.allocator);
            defer new_prefix.deinit();

            try new_prefix.appendSlice(prefix);
            if (is_child_last) {
                try new_prefix.appendSlice("    ");
            } else {
                try new_prefix.appendSlice("│   ");
            }

            try printTreeRecursive(child, writer, new_prefix.items, is_child_last);
        }
    }
}

/// Detect circular dependencies
pub fn detectCycles(
    root: *GraphNode,
    allocator: std.mem.Allocator,
) !?[]const []const u8 {
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var path = std.ArrayList([]const u8).init(allocator);
    defer path.deinit();

    return try detectCyclesRecursive(root, &visited, &path, allocator);
}

fn detectCyclesRecursive(
    node: *GraphNode,
    visited: *std.StringHashMap(void),
    path: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
) !?[]const []const u8 {
    // Check if this node is already in the current path (cycle detected)
    for (path.items) |name| {
        if (std.mem.eql(u8, name, node.name)) {
            // Found a cycle! Return the path
            var cycle = try allocator.alloc([]const u8, path.items.len + 1);
            @memcpy(cycle[0..path.items.len], path.items);
            cycle[path.items.len] = try allocator.dupe(u8, node.name);
            return cycle;
        }
    }

    // Add to path
    try path.append(node.name);
    defer _ = path.pop();

    // Visit children
    for (node.children.items) |child| {
        if (try detectCyclesRecursive(child, visited, path, allocator)) |cycle| {
            return cycle;
        }
    }

    // Mark as visited
    try visited.put(node.name, {});

    return null;
}

/// Calculate dependency statistics
pub const DepStats = struct {
    total_deps: usize,
    unique_deps: usize,
    max_depth: usize,
    total_size: usize, // In bytes (if available)
};

pub fn calculateStats(root: *GraphNode, allocator: std.mem.Allocator) !DepStats {
    var unique = std.StringHashMap(void).init(allocator);
    defer unique.deinit();

    var total: usize = 0;
    var max_depth: usize = 0;

    try countDepsRecursive(root, &unique, &total, &max_depth, 0);

    return DepStats{
        .total_deps = total,
        .unique_deps = unique.count(),
        .max_depth = max_depth,
        .total_size = 0, // TODO: Calculate from cache
    };
}

fn countDepsRecursive(
    node: *GraphNode,
    unique: *std.StringHashMap(void),
    total: *usize,
    max_depth: *usize,
    current_depth: usize,
) !void {
    try unique.put(node.name, {});
    const new_total = total.* + 1;
    total.* = new_total;

    const new_max = if (current_depth > max_depth.*) current_depth else max_depth.*;
    max_depth.* = new_max;

    for (node.children.items) |child| {
        try countDepsRecursive(child, unique, total, max_depth, current_depth + 1);
    }
}

test "graph node creation" {
    const allocator = std.testing.allocator;

    const root = try GraphNode.init(allocator, "my-project", "1.0.0");
    defer root.deinit();

    const child1 = try GraphNode.init(allocator, "zsync", "0.7.1");
    try root.addChild(child1);

    const child2 = try GraphNode.init(allocator, "zhttp", "0.1.4");
    try root.addChild(child2);

    try std.testing.expectEqual(@as(usize, 2), root.children.items.len);
}

test "detect simple cycle" {
    const allocator = std.testing.allocator;

    const root = try GraphNode.init(allocator, "A", "1.0.0");
    defer root.deinit();

    const child = try GraphNode.init(allocator, "B", "1.0.0");
    try root.addChild(child);

    // Create cycle: B -> A
    const cycle_node = try GraphNode.init(allocator, "A", "1.0.0");
    try child.addChild(cycle_node);

    const cycle = try detectCycles(root, allocator);
    try std.testing.expect(cycle != null);
    if (cycle) |c| {
        defer allocator.free(c);
        for (c) |name| allocator.free(name);
    }
}
