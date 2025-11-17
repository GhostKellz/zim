const std = @import("std");
const color = @import("../util/color.zig");

/// Check for outdated dependencies and optionally update them
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var interactive = false;
    var fix_mode = false;

    // Parse arguments
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--fix")) {
            fix_mode = true;
            interactive = true;
        } else if (std.mem.eql(u8, arg, "--interactive") or std.mem.eql(u8, arg, "-i")) {
            interactive = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return;
        }
    }

    const stdout = std.io.getStdOut().writer();

    color.info("\n📦 \x1B[1mChecking for outdated dependencies\x1B[0m\n", .{});
    color.dim("────────────────────────────────────────\n\n", .{});

    // Get outdated packages
    var outdated = try getOutdatedPackages(allocator);
    defer {
        for (outdated.items) |pkg| {
            allocator.free(pkg.name);
            allocator.free(pkg.current_version);
            allocator.free(pkg.latest_version);
        }
        outdated.deinit();
    }

    if (outdated.items.len == 0) {
        color.success("✅ All dependencies are up to date!\n\n", .{});
        return;
    }

    // Print outdated packages
    try stdout.print("Found \x1B[33m{d}\x1B[0m outdated package(s):\n\n", .{outdated.items.len});

    try printOutdatedTable(stdout, outdated.items);

    if (fix_mode or interactive) {
        try stdout.writeAll("\n");
        try interactiveUpdate(allocator, outdated.items);
    } else {
        color.dim("\n💡 Run with \x1B[36m--fix\x1B[0m to interactively update dependencies\n", .{});
    }
}

const OutdatedPackage = struct {
    name: []const u8,
    current_version: []const u8,
    latest_version: []const u8,
    update_type: UpdateType,

    const UpdateType = enum {
        patch, // 1.0.0 -> 1.0.1
        minor, // 1.0.0 -> 1.1.0
        major, // 1.0.0 -> 2.0.0

        fn color_code(self: UpdateType) []const u8 {
            return switch (self) {
                .patch => "\x1B[32m", // Green
                .minor => "\x1B[33m", // Yellow
                .major => "\x1B[31m", // Red
            };
        }

        fn symbol(self: UpdateType) []const u8 {
            return switch (self) {
                .patch => "↑",
                .minor => "⬆",
                .major => "⚠",
            };
        }
    };
};

fn getOutdatedPackages(allocator: std.mem.Allocator) !std.ArrayList(OutdatedPackage) {
    var packages = std.ArrayList(OutdatedPackage).init(allocator);

    // Simulate outdated packages
    // In real implementation, this would:
    // 1. Read current versions from zim.lock
    // 2. Query registry for latest versions
    // 3. Compare versions

    try packages.append(.{
        .name = try allocator.dupe(u8, "http-server"),
        .current_version = try allocator.dupe(u8, "2.0.1"),
        .latest_version = try allocator.dupe(u8, "2.1.0"),
        .update_type = .minor,
    });

    try packages.append(.{
        .name = try allocator.dupe(u8, "json-parser"),
        .current_version = try allocator.dupe(u8, "1.5.0"),
        .latest_version = try allocator.dupe(u8, "1.5.2"),
        .update_type = .patch,
    });

    try packages.append(.{
        .name = try allocator.dupe(u8, "database-client"),
        .current_version = try allocator.dupe(u8, "3.2.0"),
        .latest_version = try allocator.dupe(u8, "4.0.0"),
        .update_type = .major,
    });

    return packages;
}

fn printOutdatedTable(writer: anytype, packages: []const OutdatedPackage) !void {
    // Header
    try writer.writeAll("  \x1B[1mPackage              Current    Latest     Type\x1B[0m\n");
    try writer.writeAll("  ─────────────────────────────────────────────────\n");

    // Rows
    for (packages) |pkg| {
        const type_color = pkg.update_type.color_code();
        const type_symbol = pkg.update_type.symbol();

        try writer.print("  {s: <20} {s: <10} {s: <10} {s}{s} {s}\x1B[0m\n", .{
            pkg.name,
            pkg.current_version,
            pkg.latest_version,
            type_color,
            type_symbol,
            @tagName(pkg.update_type),
        });
    }
}

fn interactiveUpdate(allocator: std.mem.Allocator, packages: []const OutdatedPackage) !void {
    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();

    color.info("🔄 Interactive Update Mode\n", .{});
    color.dim("────────────────────────────\n\n", .{});

    var updates = std.ArrayList([]const u8).init(allocator);
    defer {
        for (updates.items) |name| {
            allocator.free(name);
        }
        updates.deinit();
    }

    for (packages) |pkg| {
        try stdout.writeAll("\n");
        try stdout.print("Update \x1B[36m{s}\x1B[0m from {s} to {s}?\n", .{
            pkg.name,
            pkg.current_version,
            pkg.latest_version,
        });

        if (pkg.update_type == .major) {
            color.warning("⚠️  Major version change - may contain breaking changes\n", .{});
        }

        try stdout.writeAll("  [Y]es / [n]o / [a]ll / [q]uit: ");

        var buffer: [10]u8 = undefined;
        const input = (try stdin.readUntilDelimiterOrEof(&buffer, '\n')) orelse "";
        const trimmed = std.mem.trim(u8, input, " \n\r\t");

        if (trimmed.len == 0 or std.mem.eql(u8, trimmed, "y") or std.mem.eql(u8, trimmed, "Y")) {
            // Update this package
            try updates.append(try allocator.dupe(u8, pkg.name));
            color.success("  ✓ Will update {s}\n", .{pkg.name});
        } else if (std.mem.eql(u8, trimmed, "a") or std.mem.eql(u8, trimmed, "A")) {
            // Update all remaining
            try updates.append(try allocator.dupe(u8, pkg.name));
            color.success("  ✓ Will update {s}\n", .{pkg.name});

            // Add all remaining packages
            const current_index = for (packages, 0..) |p, i| {
                if (std.mem.eql(u8, p.name, pkg.name)) break i;
            } else 0;

            for (packages[current_index + 1 ..]) |remaining| {
                try updates.append(try allocator.dupe(u8, remaining.name));
                color.success("  ✓ Will update {s}\n", .{remaining.name});
            }
            break;
        } else if (std.mem.eql(u8, trimmed, "q") or std.mem.eql(u8, trimmed, "Q")) {
            // Quit
            color.dim("  Cancelled\n", .{});
            break;
        } else {
            // Skip
            color.dim("  ⊘ Skipped {s}\n", .{pkg.name});
        }
    }

    if (updates.items.len == 0) {
        color.dim("\nNo packages selected for update\n\n", .{});
        return;
    }

    // Confirm updates
    try stdout.writeAll("\n");
    color.info("📝 Summary:\n", .{});
    try stdout.print("  Will update {d} package(s):\n", .{updates.items.len});
    for (updates.items) |name| {
        try stdout.print("    • {s}\n", .{name});
    }

    try stdout.writeAll("\nProceed? [Y/n]: ");
    var confirm_buffer: [10]u8 = undefined;
    const confirm = (try stdin.readUntilDelimiterOrEof(&confirm_buffer, '\n')) orelse "";
    const confirm_trimmed = std.mem.trim(u8, confirm, " \n\r\t");

    if (confirm_trimmed.len > 0 and !std.mem.eql(u8, confirm_trimmed, "y") and !std.mem.eql(u8, confirm_trimmed, "Y")) {
        color.dim("\nCancelled\n\n", .{});
        return;
    }

    // Perform updates
    try stdout.writeAll("\n");
    color.info("🔄 Updating dependencies...\n\n", .{});

    for (updates.items) |name| {
        try stdout.print("  ⬇️  Updating {s}...\n", .{name});
        std.time.sleep(500 * std.time.ns_per_ms); // Simulate download
        color.success("  ✓ Updated {s}\n", .{name});
    }

    try stdout.writeAll("\n");
    color.success("✅ All updates complete!\n", .{});
    color.dim("   Run \x1B[36mzim deps fetch\x1B[0m to download the new versions\n\n", .{});
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: zim outdated [OPTIONS]
        \\
        \\Check for outdated dependencies
        \\
        \\Options:
        \\  --fix, -f           Interactively update outdated dependencies
        \\  --interactive, -i   Interactive mode (same as --fix)
        \\  -h, --help          Show this help message
        \\
        \\Update Types:
        \\  ↑ patch   - Patch version update (1.0.0 -> 1.0.1)
        \\  ⬆ minor   - Minor version update (1.0.0 -> 1.1.0)
        \\  ⚠ major   - Major version update (1.0.0 -> 2.0.0) - may break!
        \\
        \\Examples:
        \\  zim outdated               # List outdated dependencies
        \\  zim outdated --fix         # Interactively update dependencies
        \\
        \\Interactive Mode:
        \\  When using --fix, you'll be prompted for each outdated package:
        \\    Y - Update this package
        \\    n - Skip this package
        \\    a - Update all remaining packages
        \\    q - Quit without updating
        \\
    );
}
