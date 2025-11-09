const std = @import("std");

/// Semantic version representation
pub const SemanticVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,
    pre: ?[]const u8 = null, // e.g. "dev.1225+bf9082518"

    pub fn parse(allocator: std.mem.Allocator, version_str: []const u8) !SemanticVersion {
        var it = std.mem.splitScalar(u8, version_str, '.');

        const major_str = it.next() orelse return error.InvalidVersion;
        const minor_str = it.next() orelse return error.InvalidVersion;
        const patch_and_pre = it.rest();

        // Parse major
        const major = try std.fmt.parseInt(u32, major_str, 10);
        const minor = try std.fmt.parseInt(u32, minor_str, 10);

        // Parse patch and pre-release
        var patch: u32 = 0;
        var pre: ?[]const u8 = null;

        if (std.mem.indexOfScalar(u8, patch_and_pre, '-')) |dash_idx| {
            const patch_str = patch_and_pre[0..dash_idx];
            patch = try std.fmt.parseInt(u32, patch_str, 10);
            pre = try allocator.dupe(u8, patch_and_pre[dash_idx + 1 ..]);
        } else {
            patch = try std.fmt.parseInt(u32, patch_and_pre, 10);
        }

        return SemanticVersion{
            .major = major,
            .minor = minor,
            .patch = patch,
            .pre = pre,
        };
    }

    pub fn deinit(self: *SemanticVersion, allocator: std.mem.Allocator) void {
        if (self.pre) |pre| allocator.free(pre);
    }

    pub fn toString(self: *const SemanticVersion, allocator: std.mem.Allocator) ![]const u8 {
        if (self.pre) |pre| {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}-{s}", .{ self.major, self.minor, self.patch, pre });
        } else {
            return std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{ self.major, self.minor, self.patch });
        }
    }

    /// Compare two semantic versions
    /// Returns: -1 if self < other, 0 if equal, 1 if self > other
    pub fn compare(self: *const SemanticVersion, other: *const SemanticVersion) i8 {
        // Compare major
        if (self.major < other.major) return -1;
        if (self.major > other.major) return 1;

        // Compare minor
        if (self.minor < other.minor) return -1;
        if (self.minor > other.minor) return 1;

        // Compare patch
        if (self.patch < other.patch) return -1;
        if (self.patch > other.patch) return 1;

        // Compare pre-release
        // If one has pre-release and other doesn't, the one without is greater
        if (self.pre == null and other.pre != null) return 1;
        if (self.pre != null and other.pre == null) return -1;
        if (self.pre != null and other.pre != null) {
            const cmp = std.mem.order(u8, self.pre.?, other.pre.?);
            if (cmp == .lt) return -1;
            if (cmp == .gt) return 1;
        }

        return 0;
    }

    /// Check if this version satisfies a version constraint
    pub fn satisfies(self: *const SemanticVersion, constraint: *const VersionConstraint) bool {
        return constraint.matches(self);
    }
};

/// Version constraint for dependency resolution
pub const VersionConstraint = union(enum) {
    /// Exact version (=1.2.3)
    exact: SemanticVersion,

    /// Greater than or equal (>=1.2.3)
    gte: SemanticVersion,

    /// Less than (<2.0.0)
    lt: SemanticVersion,

    /// Compatible with (^1.2.3 = >=1.2.3 <2.0.0)
    caret: SemanticVersion,

    /// Tilde range (~1.2.3 = >=1.2.3 <1.3.0)
    tilde: SemanticVersion,

    /// Wildcard (1.2.* = >=1.2.0 <1.3.0)
    wildcard: struct {
        major: u32,
        minor: ?u32,
    },

    /// Any version
    any,

    pub fn matches(self: *const VersionConstraint, version: *const SemanticVersion) bool {
        return switch (self.*) {
            .exact => |exact| version.compare(&exact) == 0,
            .gte => |gte| version.compare(&gte) >= 0,
            .lt => |lt| version.compare(&lt) < 0,
            .caret => |caret| {
                // ^1.2.3 := >=1.2.3 <2.0.0
                if (version.compare(&caret) < 0) return false;
                var upper = SemanticVersion{
                    .major = caret.major + 1,
                    .minor = 0,
                    .patch = 0,
                };
                return version.compare(&upper) < 0;
            },
            .tilde => |tilde| {
                // ~1.2.3 := >=1.2.3 <1.3.0
                if (version.compare(&tilde) < 0) return false;
                var upper = SemanticVersion{
                    .major = tilde.major,
                    .minor = tilde.minor + 1,
                    .patch = 0,
                };
                return version.compare(&upper) < 0;
            },
            .wildcard => |wc| {
                if (version.major != wc.major) return false;
                if (wc.minor) |minor| {
                    return version.minor == minor;
                }
                return true;
            },
            .any => true,
        };
    }

    /// Parse a version constraint string
    pub fn parse(allocator: std.mem.Allocator, constraint_str: []const u8) !VersionConstraint {
        if (std.mem.eql(u8, constraint_str, "*")) {
            return .any;
        }

        // Check for caret constraint (^1.2.3)
        if (std.mem.startsWith(u8, constraint_str, "^")) {
            const ver = try SemanticVersion.parse(allocator, constraint_str[1..]);
            return .{ .caret = ver };
        }

        // Check for tilde constraint (~1.2.3)
        if (std.mem.startsWith(u8, constraint_str, "~")) {
            const ver = try SemanticVersion.parse(allocator, constraint_str[1..]);
            return .{ .tilde = ver };
        }

        // Check for >= constraint
        if (std.mem.startsWith(u8, constraint_str, ">=")) {
            const ver = try SemanticVersion.parse(allocator, constraint_str[2..]);
            return .{ .gte = ver };
        }

        // Check for < constraint
        if (std.mem.startsWith(u8, constraint_str, "<")) {
            const ver = try SemanticVersion.parse(allocator, constraint_str[1..]);
            return .{ .lt = ver };
        }

        // Check for exact constraint (=1.2.3 or just 1.2.3)
        const ver_str = if (std.mem.startsWith(u8, constraint_str, "="))
            constraint_str[1..]
        else
            constraint_str;

        const ver = try SemanticVersion.parse(allocator, ver_str);
        return .{ .exact = ver };
    }

    pub fn deinit(self: *VersionConstraint, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .exact, .gte, .lt, .caret, .tilde => |*ver| ver.deinit(allocator),
            else => {},
        }
    }
};

/// Fetch Zig download index from ziglang.org
pub fn fetchZigIndex(allocator: std.mem.Allocator) !std.json.Parsed(std.json.Value) {
    // TODO: Use zhttp when we wire it up
    // For now, we'll create a placeholder structure

    const index_json =
        \\{
        \\  "master": {
        \\    "version": "0.16.0-dev.1225+bf9082518",
        \\    "date": "2025-11-08",
        \\    "linux-x86_64": {
        \\      "tarball": "https://ziglang.org/builds/zig-linux-x86_64-0.16.0-dev.1225+bf9082518.tar.xz",
        \\      "shasum": "TODO",
        \\      "size": 52428800
        \\    }
        \\  },
        \\  "0.13.0": {
        \\    "version": "0.13.0",
        \\    "date": "2024-06-06",
        \\    "linux-x86_64": {
        \\      "tarball": "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz",
        \\      "shasum": "TODO",
        \\      "size": 47185920
        \\    }
        \\  }
        \\}
    ;

    return std.json.parseFromSlice(std.json.Value, allocator, index_json, .{});
}

test "parse semantic version" {
    const allocator = std.testing.allocator;

    var v1 = try SemanticVersion.parse(allocator, "0.16.0");
    defer v1.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), v1.major);
    try std.testing.expectEqual(@as(u32, 16), v1.minor);
    try std.testing.expectEqual(@as(u32, 0), v1.patch);
    try std.testing.expect(v1.pre == null);

    var v2 = try SemanticVersion.parse(allocator, "0.16.0-dev.1225+bf9082518");
    defer v2.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 0), v2.major);
    try std.testing.expectEqual(@as(u32, 16), v2.minor);
    try std.testing.expectEqual(@as(u32, 0), v2.patch);
    try std.testing.expect(v2.pre != null);
}
