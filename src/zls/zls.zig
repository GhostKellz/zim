const std = @import("std");
const builtin = @import("builtin");
const download = @import("../util/download.zig");

/// ZLS (Zig Language Server) manager
pub const ZlsManager = struct {
    allocator: std.mem.Allocator,
    zls_dir: []const u8,
    config_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, zls_dir: []const u8, config_dir: []const u8) !ZlsManager {
        return ZlsManager{
            .allocator = allocator,
            .zls_dir = try allocator.dupe(u8, zls_dir),
            .config_dir = try allocator.dupe(u8, config_dir),
        };
    }

    pub fn deinit(self: *ZlsManager) void {
        self.allocator.free(self.zls_dir);
        self.allocator.free(self.config_dir);
    }

    /// Check if ZLS is installed (system or local)
    pub fn isInstalled(self: *ZlsManager) !bool {
        // Check system installation first
        if (self.findSystemZls()) |_| {
            return true;
        }

        // Check local installation
        const local_path = try self.getLocalZlsPath();
        defer self.allocator.free(local_path);

        var file = std.fs.openFileAbsolute(local_path, .{}) catch {
            return false;
        };
        file.close();
        return true;
    }

    /// Find system-installed ZLS
    pub fn findSystemZls(self: *ZlsManager) ?[]const u8 {
        _ = self;
        // Check common system paths
        const paths = [_][]const u8{
            "/usr/bin/zls",
            "/usr/local/bin/zls",
            "/opt/bin/zls",
        };

        for (paths) |path| {
            var file = std.fs.openFileAbsolute(path, .{}) catch continue;
            file.close();
            return path;
        }

        return null;
    }

    /// Get local ZLS path
    fn getLocalZlsPath(self: *ZlsManager) ![]const u8 {
        return std.fs.path.join(self.allocator, &[_][]const u8{ self.zls_dir, "zls" });
    }

    /// Get ZLS version
    pub fn getVersion(self: *ZlsManager) ![]const u8 {
        const zls_path = if (self.findSystemZls()) |path|
            path
        else blk: {
            const local = try self.getLocalZlsPath();
            defer self.allocator.free(local);
            break :blk try self.allocator.dupe(u8, local);
        };
        defer if (self.findSystemZls() == null) self.allocator.free(zls_path);

        // Run zls --version
        var argv = [_][]const u8{ zls_path, "--version" };

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
            return error.ZlsVersionFailed;
        }

        return self.allocator.dupe(u8, std.mem.trim(u8, stdout.items, &std.ascii.whitespace));
    }

    /// Run ZLS doctor - comprehensive health check
    pub fn doctor(self: *ZlsManager) !void {
        std.debug.print("🏥 ZLS Health Check\n\n", .{});

        // Check if ZLS is installed
        const installed = try self.isInstalled();

        if (!installed) {
            std.debug.print("❌ ZLS is not installed\n\n", .{});
            try self.printInstallInstructions();
            return;
        }

        std.debug.print("✅ ZLS is installed\n", .{});

        // Get version
        const version = self.getVersion() catch |err| {
            std.debug.print("⚠️  Could not determine ZLS version: {}\n", .{err});
            return;
        };
        defer self.allocator.free(version);

        std.debug.print("   Version: {s}\n\n", .{version});

        // Check ZLS location
        if (self.findSystemZls()) |system_path| {
            std.debug.print("📍 Location: {s} (system)\n\n", .{system_path});
        } else {
            const local_path = try self.getLocalZlsPath();
            defer self.allocator.free(local_path);
            std.debug.print("📍 Location: {s} (local)\n\n", .{local_path});
        }

        // Check Zig compatibility
        try self.checkZigCompatibility();

        // Check configuration
        try self.checkConfiguration();

        std.debug.print("\n✅ ZLS health check complete!\n", .{});
    }

    /// Check Zig compatibility
    fn checkZigCompatibility(self: *ZlsManager) !void {
        std.debug.print("🔍 Checking Zig compatibility...\n", .{});

        // Try to run zig version
        var argv = [_][]const u8{ "zig", "version" };
        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        child.spawn() catch {
            std.debug.print("⚠️  Zig is not in PATH\n", .{});
            return;
        };

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

        _ = try child.wait();

        const zig_version = std.mem.trim(u8, stdout.items, &std.ascii.whitespace);
        std.debug.print("   Zig version: {s}\n", .{zig_version});
        std.debug.print("   ✅ Zig is available\n", .{});
    }

    /// Check ZLS configuration
    fn checkConfiguration(self: *ZlsManager) !void {
        std.debug.print("\n📝 Checking configuration...\n", .{});

        const config_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.config_dir, "zls.json" },
        );
        defer self.allocator.free(config_path);

        var file = std.fs.openFileAbsolute(config_path, .{}) catch {
            std.debug.print("   ℹ️  No configuration file found\n", .{});
            std.debug.print("   Run 'zim zls config' to generate one\n", .{});
            return;
        };
        file.close();

        std.debug.print("   ✅ Configuration file exists: {s}\n", .{config_path});
    }

    /// Print installation instructions
    fn printInstallInstructions(self: *ZlsManager) !void {
        _ = self;
        std.debug.print("📦 Installation Instructions:\n\n", .{});

        switch (builtin.os.tag) {
            .linux => {
                std.debug.print("Arch Linux:\n", .{});
                std.debug.print("  sudo pacman -S zls\n\n", .{});

                std.debug.print("Ubuntu/Debian:\n", .{});
                std.debug.print("  Download from: https://github.com/zigtools/zls/releases\n\n", .{});

                std.debug.print("Fedora:\n", .{});
                std.debug.print("  sudo dnf install zls\n\n", .{});
            },
            .macos => {
                std.debug.print("macOS:\n", .{});
                std.debug.print("  brew install zls\n\n", .{});
            },
            .windows => {
                std.debug.print("Windows:\n", .{});
                std.debug.print("  Download from: https://github.com/zigtools/zls/releases\n\n", .{});
            },
            else => {
                std.debug.print("Download from: https://github.com/zigtools/zls/releases\n\n", .{});
            },
        }

        std.debug.print("Or install via ZIM:\n", .{});
        std.debug.print("  zim zls install\n", .{});
    }

    /// Install ZLS from GitHub releases
    pub fn install(self: *ZlsManager, version: ?[]const u8) !void {
        const target_version = version orelse "latest";
        std.debug.print("📦 Installing ZLS ({s})...\n\n", .{target_version});

        // For now, provide instructions
        // TODO: Implement automatic download and installation
        std.debug.print("⚠️  Automatic installation not yet implemented\n\n", .{});
        try self.printInstallInstructions();
    }

    /// Generate ZLS configuration
    pub fn generateConfig(self: *ZlsManager) !void {
        std.debug.print("📝 Generating ZLS configuration...\n\n", .{});

        // Ensure config directory exists
        std.fs.makeDirAbsolute(self.config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const config_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.config_dir, "zls.json" },
        );
        defer self.allocator.free(config_path);

        // Generate optimal ZLS configuration
        const config_content =
            \\{
            \\  "enable_snippets": true,
            \\  "enable_ast_check_diagnostics": true,
            \\  "enable_autofix": true,
            \\  "enable_import_embedfile_argument_completions": true,
            \\  "warn_style": true,
            \\  "highlight_global_var_declarations": true,
            \\  "dangerous_comptime_experiments_do_not_enable": false,
            \\  "skip_std_references": false,
            \\  "prefer_ast_check_as_child_process": true,
            \\  "record_session": false,
            \\  "replay_session_path": null,
            \\  "builtin_path": null,
            \\  "zig_lib_path": null,
            \\  "zig_exe_path": null,
            \\  "build_runner_path": null,
            \\  "global_cache_path": null,
            \\  "build_runner_cache_path": null,
            \\  "completions_with_replace": true
            \\}
            \\
        ;

        const file = try std.fs.createFileAbsolute(config_path, .{});
        defer file.close();

        try file.writeAll(config_content);

        std.debug.print("✅ Configuration generated: {s}\n\n", .{config_path});
        std.debug.print("📖 Configuration options:\n", .{});
        std.debug.print("   • Snippets enabled\n", .{});
        std.debug.print("   • AST diagnostics enabled\n", .{});
        std.debug.print("   • Auto-fix enabled\n", .{});
        std.debug.print("   • Style warnings enabled\n", .{});
        std.debug.print("   • Completions with replace enabled\n\n", .{});

        std.debug.print("💡 Tip: Restart your editor to apply changes\n", .{});
    }

    /// Update ZLS
    pub fn update(self: *ZlsManager) !void {
        std.debug.print("🔄 Updating ZLS...\n\n", .{});

        if (self.findSystemZls()) |_| {
            std.debug.print("ℹ️  System ZLS detected. Update via package manager:\n\n", .{});

            switch (builtin.os.tag) {
                .linux => {
                    std.debug.print("  sudo pacman -Syu zls    # Arch\n", .{});
                    std.debug.print("  sudo apt update && sudo apt upgrade zls  # Debian/Ubuntu\n", .{});
                    std.debug.print("  sudo dnf upgrade zls    # Fedora\n", .{});
                },
                .macos => {
                    std.debug.print("  brew upgrade zls\n", .{});
                },
                else => {
                    std.debug.print("  Update via your package manager\n", .{});
                },
            }
        } else {
            std.debug.print("⚠️  Local ZLS update not yet implemented\n", .{});
            std.debug.print("   Please reinstall: zim zls install\n", .{});
        }
    }

    /// Show ZLS information
    pub fn info(self: *ZlsManager) !void {
        std.debug.print("ℹ️  ZLS Information\n\n", .{});

        const installed = try self.isInstalled();

        if (!installed) {
            std.debug.print("Status: Not installed\n\n", .{});
            try self.printInstallInstructions();
            return;
        }

        std.debug.print("Status: Installed\n", .{});

        if (self.getVersion()) |version| {
            defer self.allocator.free(version);
            std.debug.print("Version: {s}\n", .{version});
        } else |_| {
            std.debug.print("Version: Unknown\n", .{});
        }

        if (self.findSystemZls()) |path| {
            std.debug.print("Location: {s} (system)\n", .{path});
        } else {
            const local_path = try self.getLocalZlsPath();
            defer self.allocator.free(local_path);
            std.debug.print("Location: {s} (local)\n", .{local_path});
        }

        std.debug.print("\n📚 Resources:\n", .{});
        std.debug.print("   GitHub: https://github.com/zigtools/zls\n", .{});
        std.debug.print("   Docs:   https://github.com/zigtools/zls/wiki\n", .{});
    }
};

test "zls manager init" {
    const allocator = std.testing.allocator;
    var mgr = try ZlsManager.init(allocator, "/tmp/zls", "/tmp/config");
    defer mgr.deinit();

    try std.testing.expect(mgr.zls_dir.len > 0);
}
