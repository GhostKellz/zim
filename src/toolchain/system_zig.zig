const std = @import("std");
const builtin = @import("builtin");

/// System Zig detection and management (anyzig-style)
pub const SystemZig = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SystemZig {
        return SystemZig{ .allocator = allocator };
    }

    /// Check if system Zig is installed
    pub fn isInstalled(self: *SystemZig) bool {
        return self.getPath() != null;
    }

    /// Get system Zig path
    pub fn getPath(self: *SystemZig) ?[]const u8 {
        _ = self;

        // Check common system paths
        const paths = [_][]const u8{
            "/usr/bin/zig",
            "/usr/local/bin/zig",
            "/opt/bin/zig",
            "/opt/zig/bin/zig",
        };

        for (paths) |path| {
            var file = std.fs.openFileAbsolute(path, .{}) catch continue;
            file.close();
            return path;
        }

        return null;
    }

    /// Get system Zig version
    pub fn getVersion(self: *SystemZig) !?[]const u8 {
        const zig_path = self.getPath() orelse return null;

        var argv = [_][]const u8{ zig_path, "version" };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        var stdout: std.ArrayList(u8) = .{};
        defer stdout.deinit(self.allocator);

        if (child.stdout) |stdout_pipe| {
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = try stdout_pipe.read(&buffer);
                if (bytes_read == 0) break;
                try stdout.appendSlice(self.allocator, buffer[0..bytes_read]);
            }
        }

        const term = try child.wait();
        if (term != .Exited or term.Exited != 0) {
            return null;
        }

        const trimmed = std.mem.trim(u8, stdout.items, &std.ascii.whitespace);
        const result = try self.allocator.dupe(u8, trimmed);
        return result;
    }

    /// Get detailed system Zig information
    pub fn getInfo(self: *SystemZig) !?ZigInfo {
        const path = self.getPath() orelse return null;
        const version = try self.getVersion() orelse return null;

        return ZigInfo{
            .path = try self.allocator.dupe(u8, path),
            .version = version,
            .is_system = true,
            .allocator = self.allocator,
        };
    }

    /// Print system Zig detection results
    pub fn printStatus(self: *SystemZig) !void {
        std.debug.print("🔍 System Zig Detection\n\n", .{});

        if (self.getPath()) |path| {
            std.debug.print("✅ System Zig found\n", .{});
            std.debug.print("   Path: {s}\n", .{path});

            if (try self.getVersion()) |version| {
                defer self.allocator.free(version);
                std.debug.print("   Version: {s}\n", .{version});
            }

            std.debug.print("\n💡 Use 'zim use system' to switch to system Zig\n", .{});
        } else {
            std.debug.print("❌ No system Zig installation found\n\n", .{});
            try self.printInstallInstructions();
        }
    }

    /// Print installation instructions for system Zig
    fn printInstallInstructions(self: *SystemZig) !void {
        _ = self;
        std.debug.print("📦 Install Zig via package manager:\n\n", .{});

        switch (builtin.os.tag) {
            .linux => {
                std.debug.print("Arch Linux:\n", .{});
                std.debug.print("  sudo pacman -S zig\n\n", .{});

                std.debug.print("Ubuntu/Debian (via snap):\n", .{});
                std.debug.print("  sudo snap install zig --classic --beta\n\n", .{});

                std.debug.print("Fedora:\n", .{});
                std.debug.print("  sudo dnf install zig\n\n", .{});
            },
            .macos => {
                std.debug.print("macOS:\n", .{});
                std.debug.print("  brew install zig\n\n", .{});
            },
            .windows => {
                std.debug.print("Windows (via Scoop):\n", .{});
                std.debug.print("  scoop install zig\n\n", .{});

                std.debug.print("Windows (via Chocolatey):\n", .{});
                std.debug.print("  choco install zig\n\n", .{});
            },
            else => {},
        }

        std.debug.print("Or install via ZIM:\n", .{});
        std.debug.print("  zim install 0.16.0\n", .{});
    }
};

/// Zig installation information
pub const ZigInfo = struct {
    path: []const u8,
    version: []const u8,
    is_system: bool,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ZigInfo) void {
        self.allocator.free(self.path);
        self.allocator.free(self.version);
    }

    pub fn print(self: *const ZigInfo) void {
        const source = if (self.is_system) "system" else "ZIM-managed";
        std.debug.print("Zig {s} ({s})\n", .{ self.version, source });
        std.debug.print("Location: {s}\n", .{self.path});
    }
};

/// Detect which Zig should be used (system vs ZIM-managed)
pub fn detectActiveZig(allocator: std.mem.Allocator, zim_active_path: ?[]const u8) !?ZigInfo {
    // First check if ZIM has an active version
    if (zim_active_path) |zim_path| {
        // Get version from the active ZIM installation
        const zig_binary = try std.fs.path.join(allocator, &[_][]const u8{ zim_path, "zig" });
        defer allocator.free(zig_binary);

        var argv = [_][]const u8{ zig_binary, "version" };
        var child = std.process.Child.init(&argv, allocator);
        child.stdout_behavior = .Pipe;

        child.spawn() catch |err| {
            std.debug.print("Warning: Could not get ZIM Zig version: {}\n", .{err});
            return null;
        };

        var stdout: std.ArrayList(u8) = .{};
        defer stdout.deinit(allocator);

        if (child.stdout) |stdout_pipe| {
            var buffer: [1024]u8 = undefined;
            while (true) {
                const bytes_read = try stdout_pipe.read(&buffer);
                if (bytes_read == 0) break;
                try stdout.appendSlice(allocator, buffer[0..bytes_read]);
            }
        }

        _ = try child.wait();

        const version = try allocator.dupe(u8, std.mem.trim(u8, stdout.items, &std.ascii.whitespace));

        return ZigInfo{
            .path = try allocator.dupe(u8, zim_path),
            .version = version,
            .is_system = false,
            .allocator = allocator,
        };
    }

    // Fall back to system Zig
    var system_zig = SystemZig.init(allocator);
    return try system_zig.getInfo();
}

test "system zig detection" {
    const allocator = std.testing.allocator;
    var system_zig = SystemZig.init(allocator);

    // This test will pass or fail depending on system configuration
    _ = system_zig.isInstalled();
}
