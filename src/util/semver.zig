const std = @import("std");

/// Semantic version structure following semver.org specification
pub const Version = struct {
    major: u32,
    minor: u32,
    patch: u32,
    prerelease: ?[]const u8 = null,
    build: ?[]const u8 = null,

    const Self = @This();

    /// Parse a semantic version string like "1.2.3", "1.2.3-alpha.1", "1.2.3+build.1"
    pub fn parse(allocator: std.mem.Allocator, version_str: []const u8) !Self {
        var parts = std.mem.splitSequence(u8, version_str, "+");
        const version_part = parts.first();
        const build_part = parts.next();

        var pre_parts = std.mem.splitSequence(u8, version_part, "-");
        const core_version = pre_parts.first();

        // Collect prerelease parts
        var prerelease: ?[]const u8 = null;
        if (pre_parts.next()) |_| {
            const pre_start = core_version.len + 1;
            if (pre_start > version_part.len) return error.InvalidVersion;
            prerelease = try allocator.dupe(u8, version_part[pre_start..]);
        }

        // Parse major.minor.patch
        var version_parts = std.mem.splitSequence(u8, core_version, ".");
        const major_str = version_parts.next() orelse return error.InvalidVersion;
        const minor_str = version_parts.next() orelse return error.InvalidVersion;
        const patch_str = version_parts.next() orelse return error.InvalidVersion;

        if (version_parts.next() != null) return error.InvalidVersion; // Too many parts

        const major = std.fmt.parseInt(u32, major_str, 10) catch return error.InvalidVersion;
        const minor = std.fmt.parseInt(u32, minor_str, 10) catch return error.InvalidVersion;
        const patch = std.fmt.parseInt(u32, patch_str, 10) catch return error.InvalidVersion;

        var build_metadata: ?[]const u8 = null;
        if (build_part) |build| {
            build_metadata = try allocator.dupe(u8, build);
        }

        return Self{
            .major = major,
            .minor = minor,
            .patch = patch,
            .prerelease = prerelease,
            .build = build_metadata,
        };
    }

    /// Format version as string
    pub fn format(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var result = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });

        if (self.prerelease) |pre| {
            const updated = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ result, pre });
            allocator.free(result);
            result = updated;
        }

        if (self.build) |build| {
            const updated = try std.fmt.allocPrint(allocator, "{s}+{s}", .{ result, build });
            allocator.free(result);
            result = updated;
        }

        return result;
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.prerelease) |pre| allocator.free(pre);
        if (self.build) |build| allocator.free(build);
    }

    pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
        return Self{
            .major = self.major,
            .minor = self.minor,
            .patch = self.patch,
            .prerelease = if (self.prerelease) |pre| try allocator.dupe(u8, pre) else null,
            .build = if (self.build) |build| try allocator.dupe(u8, build) else null,
        };
    }

    /// Compare two semantic versions following semver precedence rules
    pub fn order(self: Self, other: Self) std.math.Order {
        // Compare major.minor.patch
        if (self.major != other.major) return std.math.order(self.major, other.major);
        if (self.minor != other.minor) return std.math.order(self.minor, other.minor);
        if (self.patch != other.patch) return std.math.order(self.patch, other.patch);

        // Prerelease versions have lower precedence than normal versions
        if (self.prerelease == null and other.prerelease != null) return .gt;
        if (self.prerelease != null and other.prerelease == null) return .lt;
        if (self.prerelease == null and other.prerelease == null) return .eq;

        // Compare prerelease versions lexically
        return std.mem.order(u8, self.prerelease.?, other.prerelease.?);
    }

    pub fn eql(self: Self, other: Self) bool {
        return self.order(other) == .eq;
    }
};

/// Version constraint types supporting npm-style ranges
pub const Constraint = union(enum) {
    any, // *
    exact: Version, // ==1.2.3
    caret: Version, // ^1.2.3 (compatible with)
    tilde: Version, // ~1.2.3 (approximately equivalent)
    gt: Version, // >1.2.3
    gte: Version, // >=1.2.3
    lt: Version, // <1.2.3
    lte: Version, // <=1.2.3
    range: struct { // 1.2.3...2.0.0
        min: Version,
        max: Version,
    },

    const Self = @This();

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        switch (self) {
            .any => {},
            .exact, .caret, .tilde, .gt, .gte, .lt, .lte => |v| {
                var mut_v = v;
                mut_v.deinit(allocator);
            },
            .range => |r| {
                var mut_min = r.min;
                var mut_max = r.max;
                mut_min.deinit(allocator);
                mut_max.deinit(allocator);
            },
        }
    }

    /// Parse a version constraint string
    pub fn parse(allocator: std.mem.Allocator, constraint_str: []const u8) !Self {
        const trimmed = std.mem.trim(u8, constraint_str, &std.ascii.whitespace);

        // Any version
        if (std.mem.eql(u8, trimmed, "*")) {
            return .any;
        }

        // Range (1.2.3...2.0.0)
        if (std.mem.indexOf(u8, trimmed, "...")) |idx| {
            const min_str = std.mem.trim(u8, trimmed[0..idx], &std.ascii.whitespace);
            const max_str = std.mem.trim(u8, trimmed[idx + 3 ..], &std.ascii.whitespace);
            return .{
                .range = .{
                    .min = try Version.parse(allocator, min_str),
                    .max = try Version.parse(allocator, max_str),
                },
            };
        }

        // Caret (^1.2.3)
        if (std.mem.startsWith(u8, trimmed, "^")) {
            const version = try Version.parse(allocator, trimmed[1..]);
            return .{ .caret = version };
        }

        // Tilde (~1.2.3)
        if (std.mem.startsWith(u8, trimmed, "~")) {
            const version = try Version.parse(allocator, trimmed[1..]);
            return .{ .tilde = version };
        }

        // Exact (==1.2.3 or =1.2.3)
        if (std.mem.startsWith(u8, trimmed, "==")) {
            const version = try Version.parse(allocator, trimmed[2..]);
            return .{ .exact = version };
        }
        if (std.mem.startsWith(u8, trimmed, "=")) {
            const version = try Version.parse(allocator, trimmed[1..]);
            return .{ .exact = version };
        }

        // Greater than or equal (>=1.2.3)
        if (std.mem.startsWith(u8, trimmed, ">=")) {
            const version = try Version.parse(allocator, trimmed[2..]);
            return .{ .gte = version };
        }

        // Greater than (>1.2.3)
        if (std.mem.startsWith(u8, trimmed, ">")) {
            const version = try Version.parse(allocator, trimmed[1..]);
            return .{ .gt = version };
        }

        // Less than or equal (<=1.2.3)
        if (std.mem.startsWith(u8, trimmed, "<=")) {
            const version = try Version.parse(allocator, trimmed[2..]);
            return .{ .lte = version };
        }

        // Less than (<1.2.3)
        if (std.mem.startsWith(u8, trimmed, "<")) {
            const version = try Version.parse(allocator, trimmed[1..]);
            return .{ .lt = version };
        }

        // Default: treat as exact version
        const version = try Version.parse(allocator, trimmed);
        return .{ .exact = version };
    }

    /// Check if a version satisfies this constraint
    pub fn satisfies(self: Self, version: Version) bool {
        return switch (self) {
            .any => true,
            .exact => |v| version.eql(v),
            .caret => |v| satisfiesCaret(version, v),
            .tilde => |v| satisfiesTilde(version, v),
            .gt => |v| version.order(v) == .gt,
            .gte => |v| {
                const ord = version.order(v);
                return ord == .gt or ord == .eq;
            },
            .lt => |v| version.order(v) == .lt,
            .lte => |v| {
                const ord = version.order(v);
                return ord == .lt or ord == .eq;
            },
            .range => |r| {
                const min_ord = version.order(r.min);
                const max_ord = version.order(r.max);
                return (min_ord == .gt or min_ord == .eq) and (max_ord == .lt or max_ord == .eq);
            },
        };
    }
};

/// Caret range (^1.2.3) allows changes that do not modify the left-most non-zero digit
/// ^1.2.3 := >=1.2.3 <2.0.0
/// ^0.2.3 := >=0.2.3 <0.3.0
/// ^0.0.3 := >=0.0.3 <0.0.4
fn satisfiesCaret(version: Version, base: Version) bool {
    // Version must be >= base
    const ord = version.order(base);
    if (ord == .lt) return false;

    // Check upper bound based on leftmost non-zero
    if (base.major > 0) {
        return version.major == base.major;
    } else if (base.minor > 0) {
        return version.major == 0 and version.minor == base.minor;
    } else {
        return version.major == 0 and version.minor == 0 and version.patch == base.patch;
    }
}

/// Tilde range (~1.2.3) allows patch-level changes if minor version is specified
/// ~1.2.3 := >=1.2.3 <1.3.0
/// ~1.2 := >=1.2.0 <1.3.0
/// ~1 := >=1.0.0 <2.0.0
fn satisfiesTilde(version: Version, base: Version) bool {
    // Version must be >= base
    const ord = version.order(base);
    if (ord == .lt) return false;

    // Must have same major and minor
    return version.major == base.major and version.minor == base.minor;
}

// Tests
test "parse semantic version" {
    const allocator = std.testing.allocator;

    // Basic version
    {
        const v = try Version.parse(allocator, "1.2.3");
        defer v.deinit(allocator);
        try std.testing.expectEqual(@as(u32, 1), v.major);
        try std.testing.expectEqual(@as(u32, 2), v.minor);
        try std.testing.expectEqual(@as(u32, 3), v.patch);
        try std.testing.expect(v.prerelease == null);
        try std.testing.expect(v.build == null);
    }

    // With prerelease
    {
        const v = try Version.parse(allocator, "1.0.0-alpha.1");
        defer v.deinit(allocator);
        try std.testing.expectEqual(@as(u32, 1), v.major);
        try std.testing.expectEqual(@as(u32, 0), v.minor);
        try std.testing.expectEqual(@as(u32, 0), v.patch);
        try std.testing.expect(v.prerelease != null);
        try std.testing.expectEqualStrings("alpha.1", v.prerelease.?);
    }

    // With build metadata
    {
        const v = try Version.parse(allocator, "1.0.0+build.123");
        defer v.deinit(allocator);
        try std.testing.expect(v.build != null);
        try std.testing.expectEqualStrings("build.123", v.build.?);
    }
}

test "version comparison" {
    const allocator = std.testing.allocator;

    const v1 = try Version.parse(allocator, "1.0.0");
    defer v1.deinit(allocator);
    const v2 = try Version.parse(allocator, "1.0.1");
    defer v2.deinit(allocator);
    const v3 = try Version.parse(allocator, "2.0.0");
    defer v3.deinit(allocator);

    try std.testing.expectEqual(std.math.Order.lt, v1.order(v2));
    try std.testing.expectEqual(std.math.Order.lt, v1.order(v3));
    try std.testing.expectEqual(std.math.Order.lt, v2.order(v3));
    try std.testing.expectEqual(std.math.Order.eq, v1.order(v1));
}

test "parse constraints" {
    const allocator = std.testing.allocator;

    // Any version
    {
        const c = try Constraint.parse(allocator, "*");
        defer c.deinit(allocator);
        try std.testing.expect(c == .any);
    }

    // Caret
    {
        const c = try Constraint.parse(allocator, "^1.2.3");
        defer c.deinit(allocator);
        try std.testing.expect(c == .caret);
        try std.testing.expectEqual(@as(u32, 1), c.caret.major);
    }

    // Range
    {
        const c = try Constraint.parse(allocator, "1.0.0...2.0.0");
        defer c.deinit(allocator);
        try std.testing.expect(c == .range);
        try std.testing.expectEqual(@as(u32, 1), c.range.min.major);
        try std.testing.expectEqual(@as(u32, 2), c.range.max.major);
    }
}

test "constraint satisfaction - caret" {
    const allocator = std.testing.allocator;

    const constraint = try Constraint.parse(allocator, "^1.2.3");
    defer constraint.deinit(allocator);

    {
        const v = try Version.parse(allocator, "1.2.3");
        defer v.deinit(allocator);
        try std.testing.expect(constraint.satisfies(v));
    }
    {
        const v = try Version.parse(allocator, "1.3.0");
        defer v.deinit(allocator);
        try std.testing.expect(constraint.satisfies(v));
    }
    {
        const v = try Version.parse(allocator, "2.0.0");
        defer v.deinit(allocator);
        try std.testing.expect(!constraint.satisfies(v));
    }
    {
        const v = try Version.parse(allocator, "1.2.2");
        defer v.deinit(allocator);
        try std.testing.expect(!constraint.satisfies(v));
    }
}

test "constraint satisfaction - tilde" {
    const allocator = std.testing.allocator;

    const constraint = try Constraint.parse(allocator, "~1.2.3");
    defer constraint.deinit(allocator);

    {
        const v = try Version.parse(allocator, "1.2.3");
        defer v.deinit(allocator);
        try std.testing.expect(constraint.satisfies(v));
    }
    {
        const v = try Version.parse(allocator, "1.2.4");
        defer v.deinit(allocator);
        try std.testing.expect(constraint.satisfies(v));
    }
    {
        const v = try Version.parse(allocator, "1.3.0");
        defer v.deinit(allocator);
        try std.testing.expect(!constraint.satisfies(v));
    }
}
