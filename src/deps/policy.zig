const std = @import("std");
const Dependency = @import("deps.zig").Dependency;
const color = @import("../util/color.zig");

/// Policy configuration for dependency validation
pub const Policy = struct {
    allow: std.ArrayList([]const u8), // Allowed package prefixes
    deny: std.ArrayList([]const u8), // Denied package prefixes
    require_hash: bool = false, // Require hash verification for tarballs
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allow = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .deny = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable,
            .require_hash = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.allow.items) |item| {
            self.allocator.free(item);
        }
        self.allow.deinit(self.allocator);

        for (self.deny.items) |item| {
            self.allocator.free(item);
        }
        self.deny.deinit(self.allocator);
    }

    /// Load policy from JSON file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        return try parseJson(allocator, content);
    }

    /// Parse policy from JSON string
    fn parseJson(allocator: std.mem.Allocator, json_str: []const u8) !Self {
        var policy = Self.init(allocator);
        errdefer policy.deinit();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_str, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Parse allow list
        if (root.get("allow")) |allow_value| {
            const allow_array = allow_value.array;
            for (allow_array.items) |item| {
                const str = try allocator.dupe(u8, item.string);
                try policy.allow.append(allocator, str);
            }
        }

        // Parse deny list
        if (root.get("deny")) |deny_value| {
            const deny_array = deny_value.array;
            for (deny_array.items) |item| {
                const str = try allocator.dupe(u8, item.string);
                try policy.deny.append(allocator, str);
            }
        }

        // Parse require_hash
        if (root.get("require_hash")) |require_hash_value| {
            policy.require_hash = require_hash_value.bool;
        }

        return policy;
    }

    /// Validate a dependency against the policy
    pub fn validate(self: *const Self, dep: *const Dependency) !ValidationResult {
        var result = ValidationResult{
            .allowed = true,
            .violations = std.ArrayList([]const u8).initCapacity(self.allocator, 0) catch unreachable,
            .allocator = self.allocator,
        };

        // Check deny list first
        if (self.deny.items.len > 0) {
            for (self.deny.items) |pattern| {
                if (matchesPattern(dep.name, pattern)) {
                    result.allowed = false;
                    const msg = try std.fmt.allocPrint(
                        self.allocator,
                        "Package '{s}' matches deny pattern: {s}",
                        .{ dep.name, pattern },
                    );
                    try result.violations.append(self.allocator, msg);
                    return result;
                }
            }
        }

        // Check allow list (if defined, it's a whitelist)
        if (self.allow.items.len > 0) {
            var allowed = false;
            for (self.allow.items) |pattern| {
                if (matchesPattern(dep.name, pattern)) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                result.allowed = false;
                const msg = try std.fmt.allocPrint(
                    self.allocator,
                    "Package '{s}' not in allow list",
                    .{dep.name},
                );
                try result.violations.append(self.allocator, msg);
                return result;
            }
        }

        // Check hash requirement for tarballs
        if (self.require_hash) {
            switch (dep.source) {
                .tarball => |tarball| {
                    if (tarball.hash.len == 0) {
                        result.allowed = false;
                        const msg = try std.fmt.allocPrint(
                            self.allocator,
                            "Package '{s}' requires hash verification but none provided",
                            .{dep.name},
                        );
                        try result.violations.append(self.allocator, msg);
                    }
                },
                else => {},
            }
        }

        return result;
    }

    /// Audit all dependencies in a list
    pub fn audit(self: *const Self, dependencies: []const Dependency) !AuditReport {
        var report = AuditReport{
            .total = dependencies.len,
            .passed = 0,
            .failed = 0,
            .violations = std.ArrayList(Violation).initCapacity(self.allocator, 0) catch unreachable,
            .allocator = self.allocator,
        };

        for (dependencies) |dep| {
            const result = try self.validate(&dep);
            defer {
                var mut_result = result;
                mut_result.deinit();
            }

            if (result.allowed) {
                report.passed += 1;
            } else {
                report.failed += 1;
                for (result.violations.items) |violation| {
                    try report.violations.append(self.allocator, .{
                        .package = try self.allocator.dupe(u8, dep.name),
                        .message = try self.allocator.dupe(u8, violation),
                    });
                }
            }
        }

        return report;
    }
};

/// Result of validating a single dependency
pub const ValidationResult = struct {
    allowed: bool,
    violations: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ValidationResult) void {
        for (self.violations.items) |violation| {
            self.allocator.free(violation);
        }
        self.violations.deinit(self.allocator);
    }
};

/// Policy violation
pub const Violation = struct {
    package: []const u8,
    message: []const u8,

    pub fn deinit(self: *Violation, allocator: std.mem.Allocator) void {
        allocator.free(self.package);
        allocator.free(self.message);
    }
};

/// Audit report for all dependencies
pub const AuditReport = struct {
    total: usize,
    passed: usize,
    failed: usize,
    violations: std.ArrayList(Violation),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AuditReport) void {
        for (self.violations.items) |*violation| {
            violation.deinit(self.allocator);
        }
        self.violations.deinit(self.allocator);
    }

    pub fn print(self: *const AuditReport) void {
        color.info("\n📋 Policy Audit Report\n", .{});
        color.dim("─────────────────────\n", .{});

        if (self.failed == 0) {
            color.success("✓ All {d} dependencies passed policy checks\n", .{self.total});
        } else {
            color.warning("⚠ {d}/{d} dependencies failed policy checks\n", .{ self.failed, self.total });
            color.dim("\nViolations:\n", .{});

            for (self.violations.items) |violation| {
                color.error_("  ✗ {s}\n", .{violation.package});
                color.dim("    {s}\n", .{violation.message});
            }
        }
    }
};

/// Match a package name against a pattern with wildcard support
fn matchesPattern(name: []const u8, pattern: []const u8) bool {
    // Simple wildcard matching: supports "prefix/*" patterns
    if (std.mem.endsWith(u8, pattern, "/*")) {
        const prefix = pattern[0 .. pattern.len - 2];
        return std.mem.startsWith(u8, name, prefix);
    }
    if (std.mem.endsWith(u8, pattern, "*")) {
        const prefix = pattern[0 .. pattern.len - 1];
        return std.mem.startsWith(u8, name, prefix);
    }
    // Exact match
    return std.mem.eql(u8, name, pattern);
}

test "pattern matching" {
    try std.testing.expect(matchesPattern("foo/bar", "foo/*"));
    try std.testing.expect(matchesPattern("foo/bar/baz", "foo/*"));
    try std.testing.expect(!matchesPattern("bar/foo", "foo/*"));
    try std.testing.expect(matchesPattern("foobar", "foo*"));
    try std.testing.expect(matchesPattern("foo", "foo"));
}

test "policy validation" {
    const allocator = std.testing.allocator;

    var policy = Policy.init(allocator);
    defer policy.deinit();

    try policy.deny.append(allocator, try allocator.dupe(u8, "malicious/*"));
    policy.require_hash = true;

    // Test denied package
    {
        const dep = Dependency{
            .name = try allocator.dupe(u8, "malicious/package"),
            .source = .{ .git = .{ .url = try allocator.dupe(u8, "https://example.com"), .ref = try allocator.dupe(u8, "main") } },
        };
        defer {
            var mut_dep = dep;
            mut_dep.deinit(allocator);
        }

        var result = try policy.validate(&dep);
        defer result.deinit();

        try std.testing.expect(!result.allowed);
        try std.testing.expect(result.violations.items.len > 0);
    }
}
