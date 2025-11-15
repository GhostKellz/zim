const std = @import("std");
const semver = @import("../util/semver.zig");
const SemanticVersion = semver.Version;
const VersionConstraint = semver.Constraint;
const color = @import("../util/color.zig");

/// Dependency requirement
pub const Requirement = struct {
    name: []const u8,
    constraint: VersionConstraint,
    required_by: []const u8, // Parent package name

    pub fn deinit(self: *Requirement, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        var mut_constraint = self.constraint;
        mut_constraint.deinit(allocator);
        allocator.free(self.required_by);
    }
};

/// Resolved package with version
pub const ResolvedPackage = struct {
    name: []const u8,
    version: SemanticVersion,
    url: ?[]const u8 = null,
    hash: ?[]const u8 = null,

    pub fn deinit(self: *ResolvedPackage, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        var mut_version = self.version;
        mut_version.deinit(allocator);
        if (self.url) |url| allocator.free(url);
        if (self.hash) |hash| allocator.free(hash);
    }
};

/// Conflict between requirements
pub const Conflict = struct {
    package_name: []const u8,
    requirement1: Requirement,
    requirement2: Requirement,

    pub fn deinit(self: *Conflict, allocator: std.mem.Allocator) void {
        allocator.free(self.package_name);
        var req1 = self.requirement1;
        var req2 = self.requirement2;
        req1.deinit(allocator);
        req2.deinit(allocator);
    }
};

/// Dependency graph node
pub const DependencyNode = struct {
    name: []const u8,
    version: SemanticVersion,
    dependencies: std.ArrayList([]const u8), // Names of dependencies

    pub fn deinit(self: *DependencyNode, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        var mut_version = self.version;
        mut_version.deinit(allocator);
        for (self.dependencies.items) |dep| {
            allocator.free(dep);
        }
        self.dependencies.deinit();
    }
};

/// Circular dependency error
pub const CircularDependency = struct {
    cycle: std.ArrayList([]const u8), // Package names in the cycle

    pub fn deinit(self: *CircularDependency, allocator: std.mem.Allocator) void {
        for (self.cycle.items) |name| {
            allocator.free(name);
        }
        self.cycle.deinit();
    }
};

/// Dependency resolver
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    requirements: std.StringHashMap(std.ArrayList(Requirement)),
    resolved: std.StringHashMap(ResolvedPackage),
    graph: std.StringHashMap(DependencyNode), // Dependency graph

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{
            .allocator = allocator,
            .requirements = std.StringHashMap(std.ArrayList(Requirement)).init(allocator),
            .resolved = std.StringHashMap(ResolvedPackage).init(allocator),
            .graph = std.StringHashMap(DependencyNode).init(allocator),
        };
    }

    pub fn deinit(self: *Resolver) void {
        // Free requirements
        var req_it = self.requirements.iterator();
        while (req_it.next()) |entry| {
            for (entry.value_ptr.items) |*req| {
                req.deinit(self.allocator);
            }
            entry.value_ptr.deinit();
        }
        self.requirements.deinit();

        // Free resolved packages
        var res_it = self.resolved.iterator();
        while (res_it.next()) |entry| {
            var pkg = entry.value_ptr.*;
            pkg.deinit(self.allocator);
        }
        self.resolved.deinit();

        // Free graph
        var graph_it = self.graph.iterator();
        while (graph_it.next()) |entry| {
            var node = entry.value_ptr.*;
            node.deinit(self.allocator);
        }
        self.graph.deinit();
    }

    /// Add a requirement
    pub fn addRequirement(
        self: *Resolver,
        name: []const u8,
        constraint: VersionConstraint,
        required_by: []const u8,
    ) !void {
        const gop = try self.requirements.getOrPut(name);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(Requirement).init(self.allocator);
        }

        try gop.value_ptr.append(.{
            .name = try self.allocator.dupe(u8, name),
            .constraint = constraint,
            .required_by = try self.allocator.dupe(u8, required_by),
        });
    }

    /// Resolve all dependencies
    pub fn resolve(self: *Resolver) !void {
        // For each package with requirements
        var it = self.requirements.iterator();
        while (it.next()) |entry| {
            const package_name = entry.key_ptr.*;
            const reqs = entry.value_ptr.items;

            // Find a version that satisfies all constraints
            const chosen_version = try self.findSatisfyingVersion(package_name, reqs);

            // Add to resolved
            try self.resolved.put(package_name, chosen_version);
        }
    }

    /// Find conflicts in requirements
    pub fn detectConflicts(self: *Resolver, allocator: std.mem.Allocator) !?std.ArrayList(Conflict) {
        var conflicts = std.ArrayList(Conflict).init(allocator);

        var it = self.requirements.iterator();
        while (it.next()) |entry| {
            const package_name = entry.key_ptr.*;
            const reqs = entry.value_ptr.items;

            // Check if any pair of requirements are incompatible
            for (reqs, 0..) |req1, i| {
                for (reqs[i + 1 ..]) |req2| {
                    if (!self.areCompatible(&req1.constraint, &req2.constraint)) {
                        try conflicts.append(.{
                            .package_name = try allocator.dupe(u8, package_name),
                            .requirement1 = req1,
                            .requirement2 = req2,
                        });
                    }
                }
            }
        }

        if (conflicts.items.len == 0) {
            conflicts.deinit();
            return null;
        }

        return conflicts;
    }

    fn findSatisfyingVersion(
        self: *Resolver,
        package_name: []const u8,
        reqs: []const Requirement,
    ) !ResolvedPackage {
        // For now, we'll use a simple strategy:
        // 1. Try to use the highest version that satisfies all constraints
        // 2. In a real implementation, this would query a registry

        // Mock version for demonstration
        _ = package_name;
        _ = reqs;

        return ResolvedPackage{
            .name = try self.allocator.dupe(u8, package_name),
            .version = try SemanticVersion.parse(self.allocator, "1.0.0"),
        };
    }

    fn areCompatible(
        self: *Resolver,
        constraint1: *const VersionConstraint,
        constraint2: *const VersionConstraint,
    ) bool {
        _ = self;

        // Check if there's any version that satisfies both constraints
        // This is a simplified check - a full implementation would find the intersection
        switch (constraint1.*) {
            .any => return true,
            .exact => |v1| {
                // Exact version must satisfy the second constraint
                return constraint2.satisfies(v1);
            },
            .caret => |v1| {
                switch (constraint2.*) {
                    .any => return true,
                    .exact => |v2| return constraint1.satisfies(v2),
                    .caret => |v2| {
                        // Caret ranges are compatible if they overlap
                        // ^1.2.3 and ^1.3.0 are compatible (both allow 1.x.x)
                        // ^1.2.3 and ^2.0.0 are not compatible
                        if (v1.major != v2.major) return false;
                        return true;
                    },
                    .tilde => |v2| {
                        // Check if base versions are compatible
                        return constraint1.satisfies(v2);
                    },
                    else => return true, // Simplified for other cases
                }
            },
            .tilde => |v1| {
                switch (constraint2.*) {
                    .any => return true,
                    .exact => |v2| return constraint1.satisfies(v2),
                    .tilde => |v2| {
                        // Tilde ranges are compatible if major.minor match
                        return v1.major == v2.major and v1.minor == v2.minor;
                    },
                    .caret => |v2| return constraint2.satisfies(v1),
                    else => return true,
                }
            },
            .gte => |v1| {
                switch (constraint2.*) {
                    .any => return true,
                    .exact => |v2| return constraint1.satisfies(v2),
                    .lt, .lte => |v2| {
                        // >=1.0.0 and <2.0.0 are compatible
                        return v1.order(v2) != .gt;
                    },
                    else => return true,
                }
            },
            .gt, .lt, .lte => return true, // Simplified
            .range => |r1| {
                switch (constraint2.*) {
                    .any => return true,
                    .exact => |v2| return constraint1.satisfies(v2),
                    .range => |r2| {
                        // Ranges overlap if min1 <= max2 and min2 <= max1
                        const min_check = r1.min.order(r2.max);
                        const max_check = r2.min.order(r1.max);
                        return (min_check == .lt or min_check == .eq) and
                               (max_check == .lt or max_check == .eq);
                    },
                    else => return true,
                }
            },
        }
    }

    /// Detect circular dependencies using DFS
    pub fn detectCircularDependencies(self: *Resolver) !?CircularDependency {
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        var rec_stack = std.StringHashMap(void).init(self.allocator);
        defer rec_stack.deinit();

        var path = std.ArrayList([]const u8).init(self.allocator);
        defer path.deinit();

        var it = self.graph.iterator();
        while (it.next()) |entry| {
            const pkg_name = entry.key_ptr.*;

            if (visited.contains(pkg_name)) continue;

            if (try self.hasCycleDFS(pkg_name, &visited, &rec_stack, &path)) {
                // Found a cycle - return it
                var cycle = CircularDependency{
                    .cycle = std.ArrayList([]const u8).init(self.allocator),
                };
                for (path.items) |name| {
                    try cycle.cycle.append(try self.allocator.dupe(u8, name));
                }
                return cycle;
            }
        }

        return null;
    }

    fn hasCycleDFS(
        self: *Resolver,
        pkg_name: []const u8,
        visited: *std.StringHashMap(void),
        rec_stack: *std.StringHashMap(void),
        path: *std.ArrayList([]const u8),
    ) !bool {
        try visited.put(pkg_name, {});
        try rec_stack.put(pkg_name, {});
        try path.append(pkg_name);

        if (self.graph.get(pkg_name)) |node| {
            for (node.dependencies.items) |dep_name| {
                if (!visited.contains(dep_name)) {
                    if (try self.hasCycleDFS(dep_name, visited, rec_stack, path)) {
                        return true;
                    }
                } else if (rec_stack.contains(dep_name)) {
                    // Found a cycle
                    try path.append(dep_name);
                    return true;
                }
            }
        }

        _ = rec_stack.remove(pkg_name);
        _ = path.pop();
        return false;
    }

    /// Add a package to the dependency graph
    pub fn addToGraph(
        self: *Resolver,
        name: []const u8,
        version: SemanticVersion,
        dependencies: []const []const u8,
    ) !void {
        var deps_list = std.ArrayList([]const u8).init(self.allocator);
        for (dependencies) |dep| {
            try deps_list.append(try self.allocator.dupe(u8, dep));
        }

        try self.graph.put(name, .{
            .name = try self.allocator.dupe(u8, name),
            .version = try version.clone(self.allocator),
            .dependencies = deps_list,
        });
    }

    /// Print dependency graph as ASCII tree
    pub fn printGraph(self: *Resolver, root_package: []const u8) void {
        color.info("\n📦 Dependency Graph\n", .{});
        color.dim("─────────────────────\n\n", .{});

        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        self.printGraphNode(root_package, 0, "", &visited) catch {};
    }

    fn printGraphNode(
        self: *Resolver,
        pkg_name: []const u8,
        depth: usize,
        prefix: []const u8,
        visited: *std.StringHashMap(void),
    ) !void {
        const is_visited = visited.contains(pkg_name);

        if (self.graph.get(pkg_name)) |node| {
            // Print package name with version
            if (depth == 0) {
                color.success("{s} @ {d}.{d}.{d}\n", .{
                    pkg_name,
                    node.version.major,
                    node.version.minor,
                    node.version.patch,
                });
            } else {
                const tree_char = if (is_visited) "↻" else "├─";
                std.debug.print("{s}{s} {s} @ {d}.{d}.{d}", .{
                    prefix,
                    tree_char,
                    pkg_name,
                    node.version.major,
                    node.version.minor,
                    node.version.patch,
                });

                if (is_visited) {
                    color.dim(" (already shown)\n", .{});
                } else {
                    std.debug.print("\n", .{});
                }
            }

            // Mark as visited
            try visited.put(pkg_name, {});

            // Don't recurse if already visited (prevent infinite loops)
            if (is_visited and depth > 0) return;

            // Print dependencies
            for (node.dependencies.items, 0..) |dep_name, i| {
                const is_last = i == node.dependencies.items.len - 1;
                const new_prefix = if (depth == 0)
                    ""
                else if (is_last)
                    try std.fmt.allocPrint(self.allocator, "{s}   ", .{prefix})
                else
                    try std.fmt.allocPrint(self.allocator, "{s}│  ", .{prefix});

                defer if (depth > 0) self.allocator.free(new_prefix);

                try self.printGraphNode(dep_name, depth + 1, new_prefix, visited);
            }
        } else {
            // Package not in graph
            if (depth > 0) {
                color.dim("{s}├─ {s} (not resolved)\n", .{ prefix, pkg_name });
            }
        }
    }

    /// Print resolution summary
    pub fn printSummary(self: *Resolver) void {
        color.info("\n📊 Dependency Resolution Summary\n", .{});
        color.dim("──────────────────────────────────\n", .{});
        std.debug.print("  Total packages: {d}\n", .{self.resolved.count()});
        std.debug.print("  Requirements: {d}\n\n", .{self.requirements.count()});

        var it = self.resolved.iterator();
        while (it.next()) |entry| {
            color.success("  ✓ {s} @ {d}.{d}.{d}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.version.major,
                entry.value_ptr.version.minor,
                entry.value_ptr.version.patch,
            });
        }
    }
};

test "basic resolver" {
    const allocator = std.testing.allocator;

    var resolver = Resolver.init(allocator);
    defer resolver.deinit();

    // Add requirements
    var constraint1 = try VersionConstraint.parse(allocator, "^1.0.0");
    try resolver.addRequirement("zsync", constraint1, "my-project");

    try resolver.resolve();

    try std.testing.expectEqual(@as(u32, 1), resolver.resolved.count());
}
