const std = @import("std");
const zhttp = @import("zhttp");
const zcrypto = @import("zcrypto");
const download = @import("download.zig");

/// Download task for parallel execution
pub const DownloadTask = struct {
    url: []const u8,
    output_path: []const u8,
    expected_hash: ?[]const u8 = null,
    description: []const u8,

    // Progress tracking
    total_bytes: usize = 0,
    downloaded_bytes: usize = 0,
    status: Status = .pending,
    error_msg: ?[]const u8 = null,

    pub const Status = enum {
        pending,
        downloading,
        verifying,
        completed,
        failed,
    };
};

/// Progress reporter for multiple downloads
pub const ProgressReporter = struct {
    tasks: []DownloadTask,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},
    start_time: i64 = 0,

    pub fn init(allocator: std.mem.Allocator, tasks: []DownloadTask) ProgressReporter {
        return .{
            .tasks = tasks,
            .allocator = allocator,
            .start_time = std.time.milliTimestamp(),
        };
    }

    /// Render beautiful progress bars
    pub fn render(self: *ProgressReporter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Clear screen and move to top
        try std.io.getStdOut().writeAll("\x1B[2J\x1B[H");

        const stdout = std.io.getStdOut().writer();

        // Header
        try stdout.writeAll("⬇️  \x1B[1mDownloading Dependencies\x1B[0m\n\n");

        // Individual task progress
        for (self.tasks, 0..) |task, i| {
            try self.renderTask(stdout, task, i + 1);
        }

        // Overall statistics
        try self.renderStats(stdout);
    }

    fn renderTask(self: *ProgressReporter, writer: anytype, task: DownloadTask, index: usize) !void {
        _ = self;

        // Status icon
        const icon = switch (task.status) {
            .pending => "⏸️ ",
            .downloading => "⬇️ ",
            .verifying => "🔍",
            .completed => "✅",
            .failed => "❌",
        };

        // Task name (truncated if too long)
        var name_buf: [40]u8 = undefined;
        const name = if (task.description.len > 38)
            try std.fmt.bufPrint(&name_buf, "{s}...", .{task.description[0..35]})
        else
            task.description;

        try writer.print("{s} [{d}] {s: <40} ", .{ icon, index, name });

        // Progress bar
        if (task.status == .downloading and task.total_bytes > 0) {
            const percent = @as(f64, @floatFromInt(task.downloaded_bytes)) /
                           @as(f64, @floatFromInt(task.total_bytes));
            const bar_width: usize = 30;
            const filled = @as(usize, @intFromFloat(percent * @as(f64, @floatFromInt(bar_width))));

            try writer.writeAll("[");
            var i: usize = 0;
            while (i < bar_width) : (i += 1) {
                if (i < filled) {
                    try writer.writeAll("█");
                } else {
                    try writer.writeAll("░");
                }
            }
            try writer.print("] {d}% ", .{@as(usize, @intFromFloat(percent * 100))});

            // Size and speed
            try self.renderSize(writer, task.downloaded_bytes);
            try writer.writeAll(" / ");
            try self.renderSize(writer, task.total_bytes);
        } else if (task.status == .completed) {
            try writer.writeAll("\x1B[32m✓ Complete\x1B[0m");
        } else if (task.status == .failed) {
            try writer.writeAll("\x1B[31m✗ Failed\x1B[0m");
            if (task.error_msg) |err| {
                try writer.print(" ({s})", .{err});
            }
        } else if (task.status == .verifying) {
            try writer.writeAll("\x1B[33m⟳ Verifying hash...\x1B[0m");
        }

        try writer.writeAll("\n");
    }

    fn renderSize(self: *ProgressReporter, writer: anytype, bytes: usize) !void {
        _ = self;

        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        const mb = kb / 1024.0;

        if (mb >= 1.0) {
            try writer.print("{d:.1} MB", .{mb});
        } else if (kb >= 1.0) {
            try writer.print("{d:.1} KB", .{kb});
        } else {
            try writer.print("{d} B", .{bytes});
        }
    }

    fn renderStats(self: *ProgressReporter, writer: anytype) !void {
        var completed: usize = 0;
        var failed: usize = 0;
        var total_downloaded: usize = 0;
        var total_size: usize = 0;

        for (self.tasks) |task| {
            if (task.status == .completed) completed += 1;
            if (task.status == .failed) failed += 1;
            total_downloaded += task.downloaded_bytes;
            total_size += task.total_bytes;
        }

        const elapsed = std.time.milliTimestamp() - self.start_time;
        const elapsed_sec = @as(f64, @floatFromInt(elapsed)) / 1000.0;
        const speed = if (elapsed_sec > 0)
            @as(f64, @floatFromInt(total_downloaded)) / elapsed_sec / 1024.0
        else
            0.0;

        try writer.writeAll("\n");
        try writer.print("📊 Progress: {d}/{d} completed", .{ completed, self.tasks.len });
        if (failed > 0) {
            try writer.print(" \x1B[31m({d} failed)\x1B[0m", .{failed});
        }
        try writer.writeAll("\n");

        if (total_size > 0) {
            try writer.writeAll("📦 Total: ");
            try self.renderSize(writer, total_downloaded);
            try writer.writeAll(" / ");
            try self.renderSize(writer, total_size);
            try writer.writeAll("\n");
        }

        try writer.print("⚡ Speed: {d:.1} KB/s", .{speed});
        try writer.print(" | ⏱️  Time: {d:.1}s\n", .{elapsed_sec});
    }

    /// Update task progress
    pub fn updateProgress(
        self: *ProgressReporter,
        task_index: usize,
        downloaded: usize,
        total: usize,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (task_index < self.tasks.len) {
            self.tasks[task_index].downloaded_bytes = downloaded;
            self.tasks[task_index].total_bytes = total;
            if (self.tasks[task_index].status == .pending) {
                self.tasks[task_index].status = .downloading;
            }
        }
    }

    /// Mark task as complete
    pub fn markComplete(self: *ProgressReporter, task_index: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (task_index < self.tasks.len) {
            self.tasks[task_index].status = .completed;
        }
    }

    /// Mark task as failed
    pub fn markFailed(self: *ProgressReporter, task_index: usize, err_msg: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (task_index < self.tasks.len) {
            self.tasks[task_index].status = .failed;
            self.tasks[task_index].error_msg = err_msg;
        }
    }
};

/// Download multiple files in parallel
pub fn downloadParallel(
    allocator: std.mem.Allocator,
    tasks: []DownloadTask,
    max_concurrent: usize,
) !void {
    var reporter = ProgressReporter.init(allocator, tasks);

    // Create thread pool
    var pool = std.Thread.Pool{};
    try pool.init(.{ .allocator = allocator, .n_jobs = max_concurrent });
    defer pool.deinit();

    // Render thread
    const render_thread = try std.Thread.spawn(.{}, renderLoop, .{ &reporter });
    defer render_thread.join();

    // Spawn download tasks
    for (tasks, 0..) |*task, i| {
        try pool.spawn(downloadWorker, .{ allocator, task, &reporter, i });
    }

    // Wait for all downloads
    pool.waitAndWork();

    // Final render
    try reporter.render();
    std.debug.print("\n", .{});
}

/// Worker thread for downloading
fn downloadWorker(
    allocator: std.mem.Allocator,
    task: *DownloadTask,
    reporter: *ProgressReporter,
    index: usize,
) void {
    // Download the file
    if (task.expected_hash) |hash| {
        download.downloadFileVerified(
            allocator,
            task.url,
            task.output_path,
            hash,
        ) catch |err| {
            const err_str = @errorName(err);
            reporter.markFailed(index, err_str);
            return;
        };
    } else {
        download.downloadFile(
            allocator,
            task.url,
            task.output_path,
        ) catch |err| {
            const err_str = @errorName(err);
            reporter.markFailed(index, err_str);
            return;
        };
    }

    reporter.markComplete(index);
}

/// Render loop for live progress
fn renderLoop(reporter: *ProgressReporter) void {
    while (true) {
        reporter.render() catch {};
        std.time.sleep(100 * std.time.ns_per_ms); // 100ms refresh

        // Check if all done
        var all_done = true;
        for (reporter.tasks) |task| {
            if (task.status != .completed and task.status != .failed) {
                all_done = false;
                break;
            }
        }
        if (all_done) break;
    }
}

/// Simple spinner for single operations
pub const Spinner = struct {
    message: []const u8,
    running: std.atomic.Value(bool),
    thread: ?std.Thread = null,
    frames: []const []const u8 = &[_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },

    pub fn start(allocator: std.mem.Allocator, message: []const u8) !*Spinner {
        const spinner = try allocator.create(Spinner);
        spinner.* = .{
            .message = message,
            .running = std.atomic.Value(bool).init(true),
        };

        spinner.thread = try std.Thread.spawn(.{}, spinnerLoop, .{spinner});
        return spinner;
    }

    pub fn stop(self: *Spinner, allocator: std.mem.Allocator, success: bool) void {
        self.running.store(false, .seq_cst);
        if (self.thread) |thread| {
            thread.join();
        }

        // Clear line and print final status
        std.debug.print("\r\x1B[K", .{});
        if (success) {
            std.debug.print("✅ {s}\n", .{self.message});
        } else {
            std.debug.print("❌ {s}\n", .{self.message});
        }

        allocator.destroy(self);
    }

    fn spinnerLoop(self: *Spinner) void {
        var frame: usize = 0;
        while (self.running.load(.seq_cst)) {
            std.debug.print("\r{s} {s}", .{
                self.frames[frame % self.frames.len],
                self.message,
            });

            frame += 1;
            std.time.sleep(80 * std.time.ns_per_ms);
        }
    }
};
