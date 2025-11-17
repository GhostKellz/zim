const std = @import("std");
const file_watcher = @import("../util/file_watcher.zig");
const color = @import("../util/color.zig");

/// Watch mode for hot reload during development
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Parse arguments
    var watch_paths = std.ArrayList([]const u8).init(allocator);
    defer watch_paths.deinit();

    var build_command: ?[]const u8 = null;
    var clear_screen = true;
    var debounce_ms: u64 = 300;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--command") or std.mem.eql(u8, arg, "-c")) {
            i += 1;
            if (i >= args.len) {
                try stdout.writeAll("Error: --command requires an argument\n");
                return error.InvalidArgument;
            }
            build_command = args[i];
        } else if (std.mem.eql(u8, arg, "--no-clear")) {
            clear_screen = false;
        } else if (std.mem.eql(u8, arg, "--debounce")) {
            i += 1;
            if (i >= args.len) {
                try stdout.writeAll("Error: --debounce requires an argument\n");
                return error.InvalidArgument;
            }
            debounce_ms = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(stdout);
            return;
        } else {
            // Assume it's a path to watch
            try watch_paths.append(arg);
        }
    }

    // Default watch paths if none provided
    if (watch_paths.items.len == 0) {
        try watch_paths.append("src");
        try watch_paths.append("build.zig");
        try watch_paths.append("build.zig.zon");
    }

    // Default build command
    if (build_command == null) {
        build_command = "zig build";
    }

    color.info("\n👀 \x1B[1mZIM Watch Mode\x1B[0m\n", .{});
    color.dim("────────────────────────────\n\n", .{});
    try stdout.print("  Command: \x1B[36m{s}\x1B[0m\n", .{build_command.?});
    try stdout.writeAll("  Watching:\n");
    for (watch_paths.items) |path| {
        try stdout.print("    • {s}\n", .{path});
    }
    try stdout.print("  Debounce: {d}ms\n", .{debounce_ms});
    color.dim("\n────────────────────────────\n\n", .{});

    // Initialize file watcher
    var watcher = file_watcher.NativeFileWatcher.init(allocator);
    defer watcher.deinit();

    // Add watch paths
    for (watch_paths.items) |path| {
        watcher.addPath(path) catch |err| {
            color.warning("⚠ Failed to watch {s}: {}\n", .{ path, err });
        };
    }

    // Run initial build
    color.info("🔨 Initial build...\n", .{});
    try runBuildCommand(allocator, build_command.?, clear_screen);

    // Create watch context
    var ctx = WatchContext{
        .allocator = allocator,
        .build_command = build_command.?,
        .clear_screen = clear_screen,
        .debounce_ms = debounce_ms,
        .last_build_time = std.time.milliTimestamp(),
    };

    // Watch for changes
    try watcher.watch(watchCallback);
    _ = &ctx; // Keep context alive
}

const WatchContext = struct {
    allocator: std.mem.Allocator,
    build_command: []const u8,
    clear_screen: bool,
    debounce_ms: u64,
    last_build_time: i64,
    mutex: std.Thread.Mutex = .{},
};

var global_ctx: ?*WatchContext = null;

fn watchCallback(changed_files: []const []const u8) !void {
    const ctx = global_ctx orelse return;

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Check debounce
    const now = std.time.milliTimestamp();
    const elapsed = now - ctx.last_build_time;
    if (elapsed < ctx.debounce_ms) {
        return; // Too soon, skip
    }

    // Print changed files
    color.info("\n📝 Changes detected:\n", .{});
    for (changed_files) |file| {
        color.dim("  • {s}\n", .{file});
    }

    // Run build
    try runBuildCommand(ctx.allocator, ctx.build_command, ctx.clear_screen);
    ctx.last_build_time = std.time.milliTimestamp();
}

fn runBuildCommand(allocator: std.mem.Allocator, command: []const u8, clear_screen: bool) !void {
    const start_time = std.time.milliTimestamp();

    if (clear_screen) {
        try std.io.getStdOut().writeAll("\x1B[2J\x1B[H"); // Clear screen
    }

    color.dim("\n────────────────────────────\n", .{});
    const now = std.time.timestamp();
    const time_info = std.time.epoch.EpochSeconds{ .secs = @intCast(now) };
    const day_seconds = time_info.getDaySeconds();
    const hours = day_seconds.getHoursIntoDay();
    const minutes = day_seconds.getMinutesIntoHour();
    const seconds = day_seconds.getSecondsIntoMinute();

    std.debug.print("⏰ {d:0>2}:{d:0>2}:{d:0>2} - Running: \x1B[36m{s}\x1B[0m\n", .{
        hours,
        minutes,
        seconds,
        command,
    });
    color.dim("────────────────────────────\n\n", .{});

    // Parse command into argv
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    var iter = std.mem.tokenizeScalar(u8, command, ' ');
    while (iter.next()) |part| {
        try argv.append(part);
    }

    // Run command
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch |err| {
        color.error_("\n❌ Build failed: {}\n", .{err});
        return;
    };
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    // Print output
    if (result.stdout.len > 0) {
        try std.io.getStdOut().writeAll(result.stdout);
    }
    if (result.stderr.len > 0) {
        try std.io.getStdErr().writeAll(result.stderr);
    }

    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    const duration_sec = @as(f64, @floatFromInt(duration)) / 1000.0;

    if (result.term.Exited == 0) {
        color.success("\n✅ Build successful in {d:.2}s\n", .{duration_sec});
    } else {
        color.error_("\n❌ Build failed in {d:.2}s (exit code: {d})\n", .{
            duration_sec,
            result.term.Exited,
        });
    }

    color.dim("\n👀 Watching for changes...\n\n", .{});
}

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: zim watch [OPTIONS] [PATHS...]
        \\
        \\Watch files for changes and automatically rebuild
        \\
        \\Options:
        \\  -c, --command <CMD>    Command to run on changes (default: "zig build")
        \\  --no-clear             Don't clear screen before each build
        \\  --debounce <MS>        Debounce delay in milliseconds (default: 300)
        \\  -h, --help             Show this help message
        \\
        \\Examples:
        \\  zim watch                          # Watch src/, build.zig, build.zig.zon
        \\  zim watch src tests                # Watch src/ and tests/ directories
        \\  zim watch -c "zig build test"      # Run tests on changes
        \\  zim watch --debounce 1000          # Wait 1s between rebuilds
        \\
        \\Features:
        \\  • Hot reload for rapid development
        \\  • Automatic rebuild on file changes
        \\  • Configurable debouncing
        \\  • Cross-platform file watching (inotify on Linux, polling fallback)
        \\  • Clear, colorized output
        \\
    );
}
