const std = @import("std");
const color = @import("../util/color.zig");
const config = @import("../config/config.zig");

/// System diagnostic result
pub const DiagnosticResult = struct {
    name: []const u8,
    status: Status,
    message: []const u8,

    pub const Status = enum {
        ok,
        warning,
        error_,
    };

    pub fn print(self: DiagnosticResult) void {
        switch (self.status) {
            .ok => color.success("  ✓ {s}: {s}\n", .{ self.name, self.message }),
            .warning => color.warning("  ⚠ {s}: {s}\n", .{ self.name, self.message }),
            .error_ => color.error_("  ✗ {s}: {s}\n", .{ self.name, self.message }),
        }
    }
};

/// Run system diagnostics
pub fn runDiagnostics(allocator: std.mem.Allocator) !void {
    color.info("\n🔍 ZIM System Diagnostics\n", .{});
    color.dim("─────────────────────────\n\n", .{});

    var results = try std.ArrayList(DiagnosticResult).initCapacity(allocator, 5);
    defer results.deinit(allocator);

    // Check Zig installation
    try results.append(allocator, try checkZigInstallation(allocator));

    // Check cache directory
    try results.append(allocator, try checkCacheDirectory(allocator));

    // Check global config
    try results.append(allocator, try checkGlobalConfig(allocator));

    // Check network connectivity
    try results.append(allocator, try checkNetworkConnectivity(allocator));

    // Check disk space
    try results.append(allocator, try checkDiskSpace(allocator));

    // Print all results
    for (results.items) |result| {
        result.print();
    }

    // Summary
    var ok_count: usize = 0;
    var warning_count: usize = 0;
    var error_count: usize = 0;

    for (results.items) |result| {
        switch (result.status) {
            .ok => ok_count += 1,
            .warning => warning_count += 1,
            .error_ => error_count += 1,
        }
    }

    color.dim("\n─────────────────────────\n", .{});
    if (error_count > 0) {
        color.error_("❌ {d} error(s), {d} warning(s), {d} ok\n", .{ error_count, warning_count, ok_count });
    } else if (warning_count > 0) {
        color.warning("⚠️  {d} warning(s), {d} ok\n", .{ warning_count, ok_count });
    } else {
        color.success("✅ All checks passed ({d} ok)\n", .{ok_count});
    }
}

fn checkZigInstallation(allocator: std.mem.Allocator) !DiagnosticResult {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "version" },
    }) catch {
        return DiagnosticResult{
            .name = "Zig Installation",
            .status = .error_,
            .message = "Zig not found in PATH",
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0) {
        const version = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
        const message = try std.fmt.allocPrint(allocator, "Zig {s} installed", .{version});
        return DiagnosticResult{
            .name = "Zig Installation",
            .status = .ok,
            .message = message,
        };
    } else {
        return DiagnosticResult{
            .name = "Zig Installation",
            .status = .error_,
            .message = "Zig command failed",
        };
    }
}

fn checkCacheDirectory(allocator: std.mem.Allocator) !DiagnosticResult {
    var cfg = config.Config.load(allocator) catch {
        return DiagnosticResult{
            .name = "Cache Directory",
            .status = .warning,
            .message = "Unable to load config",
        };
    };
    defer cfg.deinit();

    const cache_dir = cfg.getCacheDir();

    std.fs.accessAbsolute(cache_dir, .{}) catch {
        return DiagnosticResult{
            .name = "Cache Directory",
            .status = .warning,
            .message = "Cache directory does not exist (will be created)",
        };
    };

    const message = try std.fmt.allocPrint(allocator, "Cache directory exists: {s}", .{cache_dir});
    return DiagnosticResult{
        .name = "Cache Directory",
        .status = .ok,
        .message = message,
    };
}

fn checkGlobalConfig(allocator: std.mem.Allocator) !DiagnosticResult {
    var cfg = config.Config.load(allocator) catch {
        return DiagnosticResult{
            .name = "Global Config",
            .status = .warning,
            .message = "No global config found (using defaults)",
        };
    };
    defer cfg.deinit();

    return DiagnosticResult{
        .name = "Global Config",
        .status = .ok,
        .message = "Global config loaded successfully",
    };
}

fn checkNetworkConnectivity(allocator: std.mem.Allocator) !DiagnosticResult {
    // Try to resolve a common hostname
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "ping", "-c", "1", "-W", "2", "github.com" },
    }) catch {
        return DiagnosticResult{
            .name = "Network Connectivity",
            .status = .warning,
            .message = "Unable to test network (ping not available)",
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0) {
        return DiagnosticResult{
            .name = "Network Connectivity",
            .status = .ok,
            .message = "Network connectivity is working",
        };
    } else {
        return DiagnosticResult{
            .name = "Network Connectivity",
            .status = .warning,
            .message = "Network connectivity may be limited",
        };
    }
}

fn checkDiskSpace(allocator: std.mem.Allocator) !DiagnosticResult {
    var cfg = config.Config.load(allocator) catch {
        return DiagnosticResult{
            .name = "Disk Space",
            .status = .warning,
            .message = "Unable to load config",
        };
    };
    defer cfg.deinit();

    const cache_dir = cfg.getCacheDir();

    // Try to get disk space info using df
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "df", "-h", cache_dir },
    }) catch {
        return DiagnosticResult{
            .name = "Disk Space",
            .status = .warning,
            .message = "Unable to check disk space",
        };
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0) {
        return DiagnosticResult{
            .name = "Disk Space",
            .status = .ok,
            .message = "Disk space available",
        };
    } else {
        return DiagnosticResult{
            .name = "Disk Space",
            .status = .warning,
            .message = "Unable to check disk space",
        };
    }
}

/// Cache integrity check
pub fn checkCacheIntegrity(allocator: std.mem.Allocator) !void {
    color.info("\n🔍 Cache Integrity Check\n", .{});
    color.dim("────────────────────────\n\n", .{});

    var cfg = config.Config.load(allocator) catch {
        color.warning("⚠ Unable to load config\n", .{});
        return;
    };
    defer cfg.deinit();

    const cache_dir = cfg.getCacheDir();

    // Check if cache directory exists
    var dir = std.fs.openDirAbsolute(cache_dir, .{ .iterate = true }) catch {
        color.warning("⚠ Cache directory does not exist: {s}\n", .{cache_dir});
        return;
    };
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var total_files: usize = 0;
    var total_size: u64 = 0;
    var corrupted_files: usize = 0;

    color.dim("Scanning cache directory...\n\n", .{});

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            total_files += 1;

            const stat = dir.statFile(entry.path) catch continue;
            total_size += stat.size;

            // Check if file is readable
            const file = dir.openFile(entry.path, .{}) catch {
                corrupted_files += 1;
                color.error_("  ✗ Corrupted: {s}\n", .{entry.path});
                continue;
            };
            file.close();
        }
    }

    color.dim("\n────────────────────────\n", .{});
    std.debug.print("  Total files: {d}\n", .{total_files});
    std.debug.print("  Total size: {d} bytes\n", .{total_size});

    if (corrupted_files > 0) {
        color.error_("  Corrupted files: {d}\n", .{corrupted_files});
        color.warning("\n⚠ Run 'zim cache clean' to remove corrupted files\n", .{});
    } else {
        color.success("\n✅ Cache integrity OK\n", .{});
    }
}

/// Workspace diagnostics - check for manifest/lockfile drift
pub fn checkWorkspace(_: std.mem.Allocator) !void {
    color.info("\n🔍 Workspace Diagnostics\n", .{});
    color.dim("────────────────────────\n\n", .{});

    // Check if zim.toml exists
    const manifest_exists = blk: {
        std.fs.cwd().access("zim.toml", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!manifest_exists) {
        color.error_("✗ No zim.toml found in current directory\n", .{});
        color.dim("  Run 'zim init' to create a new project\n", .{});
        return;
    }

    color.success("✓ Found zim.toml\n", .{});

    // Check if zim.lock exists
    const lockfile_exists = blk: {
        std.fs.cwd().access("zim.lock", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!lockfile_exists) {
        color.warning("⚠ No zim.lock found\n", .{});
        color.dim("  Run 'zim deps fetch' to generate lockfile\n", .{});
        return;
    }

    color.success("✓ Found zim.lock\n", .{});

    // Check for manifest/lockfile drift
    const manifest_stat = try std.fs.cwd().statFile("zim.toml");
    const lockfile_stat = try std.fs.cwd().statFile("zim.lock");

    // Compare timestamps - newer files have higher nanosecond values
    const manifest_newer = manifest_stat.mtime.nanoseconds > lockfile_stat.mtime.nanoseconds;

    if (manifest_newer) {
        color.warning("\n⚠ Manifest is newer than lockfile\n", .{});
        color.dim("  zim.toml has been modified since last fetch\n", .{});
        color.dim("  Run 'zim deps fetch' to update lockfile\n", .{});
    } else {
        color.success("\n✅ Manifest and lockfile are in sync\n", .{});
    }

    // Check build.zig.zon if it exists
    const zon_exists = blk: {
        std.fs.cwd().access("build.zig.zon", .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (zon_exists) {
        const zon_stat = try std.fs.cwd().statFile("build.zig.zon");

        const lockfile_newer = lockfile_stat.mtime.nanoseconds > zon_stat.mtime.nanoseconds;

        if (lockfile_newer) {
            color.warning("\n⚠ Lockfile is newer than build.zig.zon\n", .{});
            color.dim("  Run 'zim deps export' to update build.zig.zon\n", .{});
        } else {
            color.success("✓ build.zig.zon is up to date\n", .{});
        }
    }
}
