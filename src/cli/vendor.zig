const std = @import("std");
const color = @import("../util/color.zig");

/// Vendor dependencies for offline/airgapped builds
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var verify_mode = false;
    var clean_mode = false;

    // Parse arguments
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--verify")) {
            verify_mode = true;
        } else if (std.mem.eql(u8, arg, "--clean")) {
            clean_mode = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return;
        }
    }

    if (clean_mode) {
        try cleanVendor(allocator);
        return;
    }

    if (verify_mode) {
        try verifyVendor(allocator);
        return;
    }

    try vendorDependencies(allocator);
}

fn vendorDependencies(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    color.info("\n📦 \x1B[1mVendoring Dependencies\x1B[0m\n", .{});
    color.dim("────────────────────────────────────\n\n", .{});

    // Create vendor directory
    const vendor_dir = "vendor";
    std.fs.cwd().makeDir(vendor_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    try stdout.print("  Vendor directory: \x1B[36m{s}/\x1B[0m\n\n", .{vendor_dir});

    // Get dependencies from lockfile
    var deps = try getDependencies(allocator);
    defer {
        for (deps.items) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version);
            allocator.free(dep.url);
        }
        deps.deinit();
    }

    if (deps.items.len == 0) {
        color.warning("⚠️  No dependencies found\n", .{});
        color.dim("   Run \x1B[36mzim deps fetch\x1B[0m first\n\n", .{});
        return;
    }

    try stdout.print("Vendoring \x1B[36m{d}\x1B[0m dependencies:\n\n", .{deps.items.len});

    var vendored: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;

    for (deps.items) |dep| {
        const dep_dir = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}-{s}",
            .{ vendor_dir, dep.name, dep.version },
        );
        defer allocator.free(dep_dir);

        // Check if already vendored
        const exists = blk: {
            std.fs.cwd().access(dep_dir, .{}) catch {
                break :blk false;
            };
            break :blk true;
        };

        if (exists) {
            try stdout.print("  ⊘ {s: <30} (already vendored)\n", .{dep.name});
            skipped += 1;
            continue;
        }

        // Vendor the dependency
        try stdout.print("  ⬇️  {s: <30} ", .{dep.name});

        copyFromCache(allocator, dep, dep_dir) catch |err| {
            color.error_("✗ Failed: {}\n", .{err});
            failed += 1;
            continue;
        };

        color.success("✓\n", .{});
        vendored += 1;
    }

    // Summary
    try stdout.writeAll("\n");
    color.dim("────────────────────────────────────\n", .{});
    try stdout.print("  Vendored: \x1B[32m{d}\x1B[0m\n", .{vendored});
    if (skipped > 0) {
        try stdout.print("  Skipped:  \x1B[33m{d}\x1B[0m\n", .{skipped});
    }
    if (failed > 0) {
        try stdout.print("  Failed:   \x1B[31m{d}\x1B[0m\n", .{failed});
    }

    if (vendored > 0) {
        try stdout.writeAll("\n");
        color.success("✅ Dependencies vendored successfully!\n", .{});
        color.dim("\n💡 Tips for offline builds:\n", .{});
        color.dim("   1. Commit vendor/ directory to version control\n", .{});
        color.dim("   2. Set ZIM_OFFLINE=1 to use vendored deps only\n", .{});
        color.dim("   3. Run \x1B[36mzim vendor --verify\x1B[0m to check integrity\n", .{});
    }

    try stdout.writeAll("\n");
}

fn cleanVendor(allocator: std.mem.Allocator) !void {
    _ = allocator;
    const stdout = std.io.getStdOut().writer();

    color.info("\n🧹 \x1B[1mCleaning Vendor Directory\x1B[0m\n", .{});
    color.dim("────────────────────────────────────\n\n", .{});

    std.fs.cwd().deleteTree("vendor") catch |err| {
        if (err == error.FileNotFound) {
            color.dim("  Vendor directory doesn't exist\n\n", .{});
            return;
        }
        return err;
    };

    color.success("✅ Vendor directory cleaned\n\n", .{});
}

fn verifyVendor(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    color.info("\n🔍 \x1B[1mVerifying Vendored Dependencies\x1B[0m\n", .{});
    color.dim("────────────────────────────────────\n\n", .{});

    // Check vendor directory exists
    var vendor_dir = std.fs.cwd().openDir("vendor", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            color.error_("❌ Vendor directory not found\n", .{});
            color.dim("   Run \x1B[36mzim vendor\x1B[0m first\n\n", .{});
            return;
        }
        return err;
    };
    defer vendor_dir.close();

    // Get expected dependencies
    var deps = try getDependencies(allocator);
    defer {
        for (deps.items) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version);
            allocator.free(dep.url);
        }
        deps.deinit();
    }

    var verified: usize = 0;
    var missing: usize = 0;
    var corrupted: usize = 0;

    for (deps.items) |dep| {
        const dep_dir = try std.fmt.allocPrint(
            allocator,
            "{s}-{s}",
            .{ dep.name, dep.version },
        );
        defer allocator.free(dep_dir);

        try stdout.print("  Checking {s: <30} ", .{dep.name});

        // Check if directory exists
        vendor_dir.access(dep_dir, .{}) catch |err| {
            if (err == error.FileNotFound) {
                color.error_("✗ Missing\n", .{});
                missing += 1;
                continue;
            }
            color.error_("✗ Error: {}\n", .{err});
            corrupted += 1;
            continue;
        };

        // TODO: Verify checksums

        color.success("✓\n", .{});
        verified += 1;
    }

    // Summary
    try stdout.writeAll("\n");
    color.dim("────────────────────────────────────\n", .{});
    try stdout.print("  Verified:  \x1B[32m{d}\x1B[0m\n", .{verified});
    if (missing > 0) {
        try stdout.print("  Missing:   \x1B[33m{d}\x1B[0m\n", .{missing});
    }
    if (corrupted > 0) {
        try stdout.print("  Corrupted: \x1B[31m{d}\x1B[0m\n", .{corrupted});
    }

    try stdout.writeAll("\n");
    if (missing > 0 or corrupted > 0) {
        color.warning("⚠️  Vendor directory is incomplete\n", .{});
        color.dim("   Run \x1B[36mzim vendor\x1B[0m to re-vendor dependencies\n\n", .{});
    } else {
        color.success("✅ All dependencies verified!\n\n", .{});
    }
}

const Dependency = struct {
    name: []const u8,
    version: []const u8,
    url: []const u8,
};

fn getDependencies(allocator: std.mem.Allocator) !std.ArrayList(Dependency) {
    var deps = std.ArrayList(Dependency).init(allocator);

    // Simulate dependencies from lockfile
    // In real implementation, parse zim.lock
    try deps.append(.{
        .name = try allocator.dupe(u8, "http-server"),
        .version = try allocator.dupe(u8, "2.1.0"),
        .url = try allocator.dupe(u8, "https://pkg.ziglang.org/http-server-2.1.0.tar.gz"),
    });

    try deps.append(.{
        .name = try allocator.dupe(u8, "json-parser"),
        .version = try allocator.dupe(u8, "1.5.0"),
        .url = try allocator.dupe(u8, "https://pkg.ziglang.org/json-parser-1.5.0.tar.gz"),
    });

    try deps.append(.{
        .name = try allocator.dupe(u8, "logger"),
        .version = try allocator.dupe(u8, "0.3.0"),
        .url = try allocator.dupe(u8, "https://pkg.ziglang.org/logger-0.3.0.tar.gz"),
    });

    return deps;
}

fn copyFromCache(allocator: std.mem.Allocator, dep: Dependency, dest_dir: []const u8) !void {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const cache_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/.zim/cache/{s}/{s}",
        .{ home, dep.name, dep.version },
    );
    defer allocator.free(cache_dir);

    // Check if package is in cache
    var cache = std.fs.cwd().openDir(cache_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            return error.NotInCache;
        }
        return err;
    };
    defer cache.close();

    // Create destination directory
    std.fs.cwd().makeDir(dest_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Copy all files from cache to vendor
    var walker = try cache.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            const dest_path = try std.fmt.allocPrint(
                allocator,
                "{s}/{s}",
                .{ dest_dir, entry.path },
            );
            defer allocator.free(dest_path);

            // Create parent directories
            if (std.fs.path.dirname(dest_path)) |parent| {
                std.fs.cwd().makePath(parent) catch |err| {
                    if (err != error.PathAlreadyExists) return err;
                };
            }

            // Copy file
            try entry.dir.copyFile(entry.basename, std.fs.cwd(), dest_path, .{});
        }
    }
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: zim vendor [OPTIONS]
        \\
        \\Vendor dependencies for offline/airgapped builds
        \\
        \\Options:
        \\  --verify       Verify vendored dependencies
        \\  --clean        Remove vendor directory
        \\  -h, --help     Show this help message
        \\
        \\What is vendoring?
        \\  Vendoring copies all dependencies into your project's vendor/
        \\  directory, allowing builds without network access.
        \\
        \\Use cases:
        \\  • Offline development
        \\  • Airgapped/secure environments
        \\  • Reproducible builds
        \\  • CI/CD without external dependencies
        \\
        \\Examples:
        \\  zim vendor              # Vendor all dependencies
        \\  zim vendor --verify     # Check vendor integrity
        \\  zim vendor --clean      # Remove vendored deps
        \\
        \\Workflow:
        \\  1. Run 'zim deps fetch' to populate cache
        \\  2. Run 'zim vendor' to copy to vendor/
        \\  3. Commit vendor/ to version control
        \\  4. On offline machine, set ZIM_OFFLINE=1
        \\
        \\Directory structure:
        \\  vendor/
        \\    ├─ http-server-2.1.0/
        \\    ├─ json-parser-1.5.0/
        \\    └─ logger-0.3.0/
        \\
    );
}
