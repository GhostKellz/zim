const std = @import("std");
const builtin = @import("builtin");
const download = @import("../util/download.zig");
const system_zig = @import("system_zig.zig");

/// Toolchain represents a Zig compiler installation
pub const Toolchain = struct {
    version: []const u8,
    path: []const u8,
    is_local: bool = false,
    is_active: bool = false,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, version: []const u8, path: []const u8) !Toolchain {
        return Toolchain{
            .allocator = allocator,
            .version = try allocator.dupe(u8, version),
            .path = try allocator.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Toolchain) void {
        self.allocator.free(self.version);
        self.allocator.free(self.path);
    }

    pub fn getZigBinary(self: *const Toolchain, allocator: std.mem.Allocator) ![]const u8 {
        return std.fs.path.join(allocator, &[_][]const u8{ self.path, "zig" });
    }
};

/// ToolchainManager handles installing, listing, and switching between Zig versions
pub const ToolchainManager = struct {
    allocator: std.mem.Allocator,
    toolchains_dir: []const u8,
    local_toolchains_dir: []const u8 = "/data/projects/zig-toolchains",

    pub fn init(allocator: std.mem.Allocator, toolchains_dir: []const u8) !ToolchainManager {
        return ToolchainManager{
            .allocator = allocator,
            .toolchains_dir = try allocator.dupe(u8, toolchains_dir),
        };
    }

    pub fn deinit(self: *ToolchainManager) void {
        self.allocator.free(self.toolchains_dir);
    }

    /// Install a Zig version
    pub fn install(self: *ToolchainManager, version: []const u8) !void {
        std.debug.print("Installing Zig {s}...\n", .{version});

        // Check if already installed
        if (try self.isInstalled(version)) {
            std.debug.print("Zig {s} is already installed\n", .{version});
            return;
        }

        // Create toolchains directory if it doesn't exist
        try self.ensureToolchainsDir();

        // Parse version to get download info
        const download_info = try self.getDownloadInfo(version);
        defer download_info.deinit(self.allocator);

        std.debug.print("Downloading from: {s}\n", .{download_info.url});
        std.debug.print("Expected hash: {s}\n", .{download_info.hash});

        // Download tarball
        const tarball_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, "zig.tar.xz" },
        );
        defer self.allocator.free(tarball_path);

        try download.downloadFileVerified(
            self.allocator,
            download_info.url,
            tarball_path,
            download_info.hash,
        );

        // Extract to toolchain directory
        const version_dir = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, version },
        );
        defer self.allocator.free(version_dir);

        // Create version directory
        try std.fs.makeDirAbsolute(version_dir);

        // Extract tarball
        try download.extractTarXz(self.allocator, tarball_path, self.toolchains_dir);

        // Clean up tarball
        std.fs.deleteFileAbsolute(tarball_path) catch {};

        // The extracted folder will be named like "zig-linux-x86_64-0.16.0"
        // We need to rename it to just the version
        const extracted_name = try std.fmt.allocPrint(
            self.allocator,
            "zig-{s}-{s}-{s}",
            .{ detectPlatform(), detectArch(), version },
        );
        defer self.allocator.free(extracted_name);

        const extracted_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, extracted_name },
        );
        defer self.allocator.free(extracted_path);

        // Rename to version directory
        try std.fs.renameAbsolute(extracted_path, version_dir);

        std.debug.print("✓ Zig {s} installed successfully\n", .{version});
    }

    /// Switch to a specific Zig version globally (anyzig-style)
    pub fn use(self: *ToolchainManager, version: []const u8) !void {
        // Handle "system" keyword for system Zig
        if (std.mem.eql(u8, version, "system")) {
            return try self.useSystemZig();
        }

        std.debug.print("Switching to Zig {s}...\n", .{version});

        // Check if version is installed
        if (!try self.isInstalled(version)) {
            std.debug.print("Error: Zig {s} is not installed\n", .{version});
            std.debug.print("Run: zim install {s}\n", .{version});
            return error.ToolchainNotInstalled;
        }

        // Update global symlink or config
        try self.setGlobalVersion(version);

        std.debug.print("✓ Now using Zig {s}\n", .{version});
    }

    /// Use system Zig installation (anyzig-style)
    pub fn useSystemZig(self: *ToolchainManager) !void {
        var sys_zig = system_zig.SystemZig.init(self.allocator);

        if (!sys_zig.isInstalled()) {
            std.debug.print("❌ No system Zig installation found\n\n", .{});
            try sys_zig.printStatus();
            return error.SystemZigNotFound;
        }

        const version = try sys_zig.getVersion() orelse return error.SystemZigVersionUnknown;
        defer self.allocator.free(version);

        // Write a special marker for system Zig
        try self.setGlobalVersion("system");

        std.debug.print("✓ Now using system Zig ({s})\n", .{version});
        if (sys_zig.getPath()) |path| {
            std.debug.print("   Location: {s}\n", .{path});
        }
    }

    /// Show current active Zig version (anyzig-style)
    pub fn current(self: *ToolchainManager) !void {
        std.debug.print("📍 Current Zig Configuration\n\n", .{});

        const active = try self.getActiveVersion();
        defer if (active) |v| self.allocator.free(v);

        if (active) |version| {
            if (std.mem.eql(u8, version, "system")) {
                // Using system Zig
                var sys_zig = system_zig.SystemZig.init(self.allocator);
                if (try sys_zig.getInfo()) |info| {
                    defer {
                        var mut_info = info;
                        mut_info.deinit();
                    }
                    std.debug.print("Active: ", .{});
                    info.print();
                } else {
                    std.debug.print("Active: system (but not found)\n", .{});
                }
            } else {
                // Using ZIM-managed Zig
                const zig_path = try std.fs.path.join(
                    self.allocator,
                    &[_][]const u8{ self.toolchains_dir, version },
                );
                defer self.allocator.free(zig_path);

                std.debug.print("Active: Zig {s} (ZIM-managed)\n", .{version});
                std.debug.print("Location: {s}\n", .{zig_path});
            }
        } else {
            std.debug.print("No active Zig version set\n\n", .{});

            // Check for system Zig
            var sys_zig = system_zig.SystemZig.init(self.allocator);
            if (sys_zig.isInstalled()) {
                std.debug.print("💡 System Zig is available\n", .{});
                std.debug.print("   Run 'zim use system' to use it\n", .{});
            } else {
                std.debug.print("💡 Install Zig with: zim install 0.16.0\n", .{});
            }
        }
    }

    /// Pin a version to the current project
    pub fn pin(self: *ToolchainManager, version: []const u8) !void {
        std.debug.print("Pinning project to Zig {s}...\n", .{version});

        // Check if version is installed
        if (!try self.isInstalled(version)) {
            std.debug.print("Error: Zig {s} is not installed\n", .{version});
            std.debug.print("Run: zim install {s}\n", .{version});
            return error.ToolchainNotInstalled;
        }

        // Create .zim directory if it doesn't exist
        std.fs.cwd().makeDir(".zim") catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Write toolchain.toml
        const config_content = try std.fmt.allocPrint(
            self.allocator,
            \\# ZIM toolchain configuration
            \\# Generated by: zim toolchain pin {s}
            \\
            \\zig = "{s}"
            \\
            \\# Uncomment to add cross-compilation targets
            \\# targets = ["x86_64-linux-gnu", "aarch64-linux-gnu", "wasm32-wasi"]
            \\
        ,
            .{ version, version },
        );
        defer self.allocator.free(config_content);

        const file = try std.fs.cwd().createFile(".zim/toolchain.toml", .{});
        defer file.close();
        try file.writeAll(config_content);

        std.debug.print("✓ Created .zim/toolchain.toml\n", .{});
        std.debug.print("✓ Project pinned to Zig {s}\n", .{version});
    }

    /// List installed toolchains
    pub fn list(self: *ToolchainManager) !void {
        std.debug.print("Installed Zig toolchains:\n\n", .{});

        // List official toolchains
        var installed = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer {
            for (installed.items) |item| self.allocator.free(item);
            installed.deinit(self.allocator);
        }

        try self.listInstalledToolchains(&installed);

        if (installed.items.len == 0) {
            std.debug.print("  (none)\n", .{});
            std.debug.print("\nInstall a toolchain with: zim install <version>\n", .{});
            return;
        }

        const active_version = try self.getActiveVersion();
        defer if (active_version) |v| self.allocator.free(v);

        for (installed.items) |version| {
            const is_active = if (active_version) |av|
                std.mem.eql(u8, version, av)
            else
                false;

            if (is_active) {
                std.debug.print("  {s} (active)\n", .{version});
            } else {
                std.debug.print("  {s}\n", .{version});
            }
        }

        // Check for local custom toolchains
        std.debug.print("\nLocal custom toolchains:\n", .{});
        var local_found = false;
        var local_dir = std.fs.openDirAbsolute(self.local_toolchains_dir, .{ .iterate = true }) catch {
            std.debug.print("  (none)\n", .{});
            return;
        };
        defer local_dir.close();

        var it = local_dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                std.debug.print("  {s} (local)\n", .{entry.name});
                local_found = true;
            }
        }

        if (!local_found) {
            std.debug.print("  (none)\n", .{});
        }
    }

    /// Check if a version is installed
    fn isInstalled(self: *ToolchainManager, version: []const u8) !bool {
        const toolchain_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, version },
        );
        defer self.allocator.free(toolchain_path);

        var dir = std.fs.openDirAbsolute(toolchain_path, .{}) catch {
            return false;
        };
        dir.close();
        return true;
    }

    fn ensureToolchainsDir(self: *ToolchainManager) !void {
        std.fs.makeDirAbsolute(self.toolchains_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    fn setGlobalVersion(self: *ToolchainManager, version: []const u8) !void {
        // Create a symlink or write to global config
        const global_link = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, "active" },
        );
        defer self.allocator.free(global_link);

        const target_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.toolchains_dir, version },
        );
        defer self.allocator.free(target_path);

        // Remove old symlink if exists
        std.fs.deleteFileAbsolute(global_link) catch {};

        // Create new symlink (Unix-like systems)
        if (builtin.os.tag != .windows) {
            try std.fs.symLinkAbsolute(target_path, global_link, .{ .is_directory = true });
        } else {
            // On Windows, write to a config file instead
            const config_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ self.toolchains_dir, "active.txt" },
            );
            defer self.allocator.free(config_path);

            const file = try std.fs.createFileAbsolute(config_path, .{});
            defer file.close();
            try file.writeAll(version);
        }
    }

    fn getActiveVersion(self: *ToolchainManager) !?[]const u8 {
        if (builtin.os.tag != .windows) {
            // Read symlink
            const active_link = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ self.toolchains_dir, "active" },
            );
            defer self.allocator.free(active_link);

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const target = std.fs.readLinkAbsolute(active_link, &buf) catch {
                return null;
            };

            // Extract version from path
            const basename = std.fs.path.basename(target);
            return try self.allocator.dupe(u8, basename);
        } else {
            // Read from config file
            const config_path = try std.fs.path.join(
                self.allocator,
                &[_][]const u8{ self.toolchains_dir, "active.txt" },
            );
            defer self.allocator.free(config_path);

            const file = std.fs.openFileAbsolute(config_path, .{}) catch {
                return null;
            };
            defer file.close();

            const content = try file.readToEndAlloc(self.allocator, 1024);
            return std.mem.trim(u8, content, &std.ascii.whitespace);
        }
    }

    fn listInstalledToolchains(self: *ToolchainManager, installed_list: *std.ArrayList([]const u8)) !void {
        var dir = std.fs.openDirAbsolute(self.toolchains_dir, .{ .iterate = true }) catch {
            return; // Directory doesn't exist yet
        };
        defer dir.close();

        var it = dir.iterate();
        while (try it.next()) |entry| {
            if (entry.kind == .directory) {
                // Skip 'active' symlink directory
                if (std.mem.eql(u8, entry.name, "active")) continue;

                try installed_list.append(self.allocator, try self.allocator.dupe(u8, entry.name));
            }
        }
    }

    fn getDownloadInfo(self: *ToolchainManager, version: []const u8) !DownloadInfo {
        // Determine platform
        const platform = detectPlatform();
        const arch = detectArch();

        // Build download URL
        // Format: https://ziglang.org/download/{version}/zig-{platform}-{arch}-{version}.tar.xz
        const filename = try std.fmt.allocPrint(
            self.allocator,
            "zig-{s}-{s}-{s}.tar.xz",
            .{ platform, arch, version },
        );
        defer self.allocator.free(filename);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "https://ziglang.org/download/{s}/{s}",
            .{ version, filename },
        );

        // TODO: Fetch hash from ziglang.org/download/index.json
        const hash = try self.allocator.dupe(u8, "TODO_FETCH_HASH");

        return DownloadInfo{
            .url = url,
            .hash = hash,
        };
    }
};

const DownloadInfo = struct {
    url: []const u8,
    hash: []const u8,

    fn deinit(self: *const DownloadInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.hash);
    }
};

fn detectPlatform() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => "unknown",
    };
}

fn detectArch() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        .arm => "armv7a",
        else => "unknown",
    };
}

test "toolchain init" {
    const allocator = std.testing.allocator;
    var toolchain = try Toolchain.init(allocator, "0.16.0", "/path/to/zig");
    defer toolchain.deinit();

    try std.testing.expectEqualStrings("0.16.0", toolchain.version);
    try std.testing.expectEqualStrings("/path/to/zig", toolchain.path);
}

test "detect platform" {
    const platform = detectPlatform();
    try std.testing.expect(platform.len > 0);
}
