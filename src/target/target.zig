const std = @import("std");
const builtin = @import("builtin");

/// Target represents a cross-compilation target
pub const Target = struct {
    triple: []const u8,
    arch: []const u8,
    os: []const u8,
    abi: ?[]const u8 = null,

    pub fn parse(allocator: std.mem.Allocator, triple: []const u8) !Target {
        // Parse target triple (e.g., "x86_64-linux-gnu")
        var it = std.mem.splitScalar(u8, triple, '-');

        const arch = it.next() orelse return error.InvalidTriple;
        const os = it.next() orelse return error.InvalidTriple;
        const abi = it.next();

        return Target{
            .triple = try allocator.dupe(u8, triple),
            .arch = try allocator.dupe(u8, arch),
            .os = try allocator.dupe(u8, os),
            .abi = if (abi) |a| try allocator.dupe(u8, a) else null,
        };
    }

    pub fn deinit(self: *Target, allocator: std.mem.Allocator) void {
        allocator.free(self.triple);
        allocator.free(self.arch);
        allocator.free(self.os);
        if (self.abi) |abi| allocator.free(abi);
    }
};

/// TargetManager handles cross-compilation targets
pub const TargetManager = struct {
    allocator: std.mem.Allocator,
    targets_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, targets_dir: []const u8) !TargetManager {
        return TargetManager{
            .allocator = allocator,
            .targets_dir = try allocator.dupe(u8, targets_dir),
        };
    }

    pub fn deinit(self: *TargetManager) void {
        self.allocator.free(self.targets_dir);
    }

    /// Add a cross-compilation target
    pub fn add(self: *TargetManager, triple: []const u8) !void {
        std.debug.print("Adding target: {s}\n", .{triple});

        var target = try Target.parse(self.allocator, triple);
        defer target.deinit(self.allocator);

        // Create targets directory if it doesn't exist
        try self.ensureTargetsDir();

        // Check if already added
        if (try self.isInstalled(triple)) {
            std.debug.print("Target {s} is already installed\n", .{triple});
            return;
        }

        // Create target directory
        const target_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.targets_dir, triple },
        );
        defer self.allocator.free(target_path);

        try std.fs.makeDirAbsolute(target_path);

        std.debug.print("✓ Target {s} added successfully\n", .{triple});
        std.debug.print("  Architecture: {s}\n", .{target.arch});
        std.debug.print("  OS: {s}\n", .{target.os});
        if (target.abi) |abi| {
            std.debug.print("  ABI: {s}\n", .{abi});
        }

        // Download stdlib for this target (bundled with Zig)
        // Note: The Zig standard library is target-independent and comes with the toolchain
        // For custom sysroots (libc headers, etc.), users can manually add them to the target directory
        std.debug.print("\n✓ Standard library is available (bundled with Zig toolchain)\n", .{});
        std.debug.print("  For custom sysroot/libc headers, place them in: {s}\n", .{target_path});
    }

    /// Remove a target
    pub fn remove(self: *TargetManager, triple: []const u8) !void {
        std.debug.print("Removing target: {s}\n", .{triple});

        if (!try self.isInstalled(triple)) {
            std.debug.print("Error: Target {s} is not installed\n", .{triple});
            return error.TargetNotInstalled;
        }

        const target_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.targets_dir, triple },
        );
        defer self.allocator.free(target_path);

        try std.fs.deleteTreeAbsolute(target_path);

        std.debug.print("✓ Target {s} removed\n", .{triple});
    }

    /// List installed targets
    pub fn list(self: *TargetManager) !void {
        std.debug.print("Installed cross-compilation targets:\n\n", .{});

        var dir = std.fs.openDirAbsolute(self.targets_dir, .{ .iterate = true }) catch {
            std.debug.print("  (none)\n", .{});
            std.debug.print("\nAdd a target with: zim target add <triple>\n", .{});
            return;
        };
        defer dir.close();

        var found = false;
        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                std.debug.print("  {s}\n", .{entry.name});
                found = true;
            }
        }

        if (!found) {
            std.debug.print("  (none)\n", .{});
        }

        std.debug.print("\nCommon targets:\n", .{});
        std.debug.print("  x86_64-linux-gnu       - Linux x86_64\n", .{});
        std.debug.print("  aarch64-linux-gnu      - Linux ARM64\n", .{});
        std.debug.print("  x86_64-windows-gnu     - Windows x86_64\n", .{});
        std.debug.print("  x86_64-macos           - macOS x86_64\n", .{});
        std.debug.print("  aarch64-macos          - macOS ARM64 (Apple Silicon)\n", .{});
        std.debug.print("  wasm32-wasi            - WebAssembly WASI\n", .{});
        std.debug.print("  wasm32-freestanding    - WebAssembly bare\n", .{});
    }

    fn isInstalled(self: *TargetManager, triple: []const u8) !bool {
        const target_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.targets_dir, triple },
        );
        defer self.allocator.free(target_path);

        var dir = std.fs.openDirAbsolute(target_path, .{}) catch {
            return false;
        };
        dir.close();
        return true;
    }

    fn ensureTargetsDir(self: *TargetManager) !void {
        std.fs.makeDirAbsolute(self.targets_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
};

/// Get default targets directory based on platform
pub fn getDefaultTargetsDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            return std.fs.path.join(allocator, &[_][]const u8{ home, ".zim", "targets" });
        } else |_| {
            return allocator.dupe(u8, "/tmp/zim-targets");
        }
    } else if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |appdata| {
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, "zim", "targets" });
        } else |_| {
            return allocator.dupe(u8, "C:\\Temp\\zim-targets");
        }
    } else {
        return allocator.dupe(u8, "/tmp/zim-targets");
    }
}

test "parse target triple" {
    const allocator = std.testing.allocator;

    var target = try Target.parse(allocator, "x86_64-linux-gnu");
    defer target.deinit(allocator);

    try std.testing.expectEqualStrings("x86_64", target.arch);
    try std.testing.expectEqualStrings("linux", target.os);
    try std.testing.expect(target.abi != null);
    try std.testing.expectEqualStrings("gnu", target.abi.?);
}

test "parse wasm target" {
    const allocator = std.testing.allocator;

    var target = try Target.parse(allocator, "wasm32-wasi");
    defer target.deinit(allocator);

    try std.testing.expectEqualStrings("wasm32", target.arch);
    try std.testing.expectEqualStrings("wasi", target.os);
}
