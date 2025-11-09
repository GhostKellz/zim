const std = @import("std");
const version_mod = @import("../util/version.zig");
const SemanticVersion = version_mod.SemanticVersion;
const VersionConstraint = version_mod.VersionConstraint;

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

/// Dependency resolver
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    requirements: std.StringHashMap(std.ArrayList(Requirement)),
    resolved: std.StringHashMap(ResolvedPackage),

    pub fn init(allocator: std.mem.Allocator) Resolver {
        return .{
            .allocator = allocator,
            .requirements = std.StringHashMap(std.ArrayList(Requirement)).init(allocator),
            .resolved = std.StringHashMap(ResolvedPackage).init(allocator),
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

        // Simple compatibility check
        // In a real implementation, this would be more sophisticated
        switch (constraint1.*) {
            .any => return true,
            .exact => |v1| {
                switch (constraint2.*) {
                    .any => return true,
                    .exact => |v2| return v1.compare(&v2) == 0,
                    .gte => |v2| return v1.compare(&v2) >= 0,
                    .lt => |v2| return v1.compare(&v2) < 0,
                    .caret, .tilde => return constraint2.matches(&v1),
                    .wildcard => return constraint2.matches(&v1),
                }
            },
            else => {
                // For other constraint types, we'd need to check if ranges overlap
                return true; // Simplified for now
            },
        }
    }

    /// Print resolution summary
    pub fn printSummary(self: *Resolver) void {
        std.debug.print("\nDependency Resolution Summary:\n", .{});
        std.debug.print("  Total packages: {d}\n", .{self.resolved.count()});
        std.debug.print("  Requirements: {d}\n\n", .{self.requirements.count()});

        var it = self.resolved.iterator();
        while (it.next()) |entry| {
            std.debug.print("  {s} @ {d}.{d}.{d}\n", .{
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
