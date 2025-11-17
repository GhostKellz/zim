const std = @import("std");
const builtin = @import("builtin");

/// File watcher that monitors directories for changes
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watched_paths: std.ArrayList([]const u8),
    file_mtimes: std.StringHashMap(i128),
    poll_interval_ms: u64 = 500,

    pub fn init(allocator: std.mem.Allocator) FileWatcher {
        return .{
            .allocator = allocator,
            .watched_paths = std.ArrayList([]const u8).init(allocator),
            .file_mtimes = std.StringHashMap(i128).init(allocator),
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        for (self.watched_paths.items) |path| {
            self.allocator.free(path);
        }
        self.watched_paths.deinit();

        var it = self.file_mtimes.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.file_mtimes.deinit();
    }

    /// Add a path to watch (can be file or directory)
    pub fn addPath(self: *FileWatcher, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        try self.watched_paths.append(path_copy);

        // Initialize mtimes for all files in the path
        try self.scanPath(path);
    }

    /// Scan a path and record all file mtimes
    fn scanPath(self: *FileWatcher, path: []const u8) !void {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            if (err == error.FileNotFound or err == error.IsDir) {
                // Try as directory
                var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |dir_err| {
                    if (dir_err == error.FileNotFound) return;
                    return dir_err;
                };
                defer dir.close();

                var walker = try dir.walk(self.allocator);
                defer walker.deinit();

                while (try walker.next()) |entry| {
                    if (entry.kind == .file) {
                        const full_path = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}/{s}",
                            .{ path, entry.path },
                        );
                        defer self.allocator.free(full_path);

                        const file_stat = try entry.dir.statFile(entry.basename);
                        const path_key = try self.allocator.dupe(u8, full_path);
                        try self.file_mtimes.put(path_key, file_stat.mtime);
                    }
                }
                return;
            }
            return err;
        };

        // Single file
        const path_key = try self.allocator.dupe(u8, path);
        try self.file_mtimes.put(path_key, stat.mtime);
    }

    /// Check for changes and return list of modified files
    pub fn checkForChanges(self: *FileWatcher) !std.ArrayList([]const u8) {
        var changed_files = std.ArrayList([]const u8).init(self.allocator);
        errdefer changed_files.deinit();

        for (self.watched_paths.items) |watched_path| {
            try self.checkPathForChanges(watched_path, &changed_files);
        }

        return changed_files;
    }

    fn checkPathForChanges(
        self: *FileWatcher,
        path: []const u8,
        changed_files: *std.ArrayList([]const u8),
    ) !void {
        const stat = std.fs.cwd().statFile(path) catch |err| {
            if (err == error.FileNotFound or err == error.IsDir) {
                // Directory
                var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |dir_err| {
                    if (dir_err == error.FileNotFound) return;
                    return dir_err;
                };
                defer dir.close();

                var walker = try dir.walk(self.allocator);
                defer walker.deinit();

                while (try walker.next()) |entry| {
                    if (entry.kind == .file) {
                        const full_path = try std.fmt.allocPrint(
                            self.allocator,
                            "{s}/{s}",
                            .{ path, entry.path },
                        );
                        defer self.allocator.free(full_path);

                        const file_stat = try entry.dir.statFile(entry.basename);

                        if (self.file_mtimes.get(full_path)) |old_mtime| {
                            if (file_stat.mtime != old_mtime) {
                                // File changed
                                try changed_files.append(try self.allocator.dupe(u8, full_path));
                                try self.file_mtimes.put(try self.allocator.dupe(u8, full_path), file_stat.mtime);
                            }
                        } else {
                            // New file
                            try changed_files.append(try self.allocator.dupe(u8, full_path));
                            try self.file_mtimes.put(try self.allocator.dupe(u8, full_path), file_stat.mtime);
                        }
                    }
                }
                return;
            }
            return err;
        };

        // Single file
        if (self.file_mtimes.get(path)) |old_mtime| {
            if (stat.mtime != old_mtime) {
                try changed_files.append(try self.allocator.dupe(u8, path));
                try self.file_mtimes.put(try self.allocator.dupe(u8, path), stat.mtime);
            }
        }
    }

    /// Watch for changes (blocking)
    pub fn watch(self: *FileWatcher, callback: *const fn ([]const []const u8) anyerror!void) !void {
        std.debug.print("👀 Watching for changes (polling every {d}ms)...\n", .{self.poll_interval_ms});

        while (true) {
            std.time.sleep(self.poll_interval_ms * std.time.ns_per_ms);

            var changed = try self.checkForChanges();
            defer {
                for (changed.items) |file| {
                    self.allocator.free(file);
                }
                changed.deinit();
            }

            if (changed.items.len > 0) {
                try callback(changed.items);
            }
        }
    }
};

/// Platform-specific file watcher using native APIs
pub const NativeFileWatcher = switch (builtin.os.tag) {
    .linux => LinuxInotifyWatcher,
    .macos => MacOSFSEventsWatcher,
    .windows => WindowsReadDirectoryChangesWatcher,
    else => FileWatcher, // Fall back to polling
};

/// Linux inotify-based watcher (more efficient than polling)
const LinuxInotifyWatcher = struct {
    allocator: std.mem.Allocator,
    inotify_fd: std.posix.fd_t,
    watch_descriptors: std.AutoHashMap(std.posix.fd_t, []const u8),

    pub fn init(allocator: std.mem.Allocator) !LinuxInotifyWatcher {
        const fd = try std.posix.inotify_init1(std.os.linux.IN.CLOEXEC);
        return .{
            .allocator = allocator,
            .inotify_fd = fd,
            .watch_descriptors = std.AutoHashMap(std.posix.fd_t, []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *LinuxInotifyWatcher) void {
        var it = self.watch_descriptors.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.watch_descriptors.deinit();
        std.posix.close(self.inotify_fd);
    }

    pub fn addPath(self: *LinuxInotifyWatcher, path: []const u8) !void {
        const wd = try std.posix.inotify_add_watch(
            self.inotify_fd,
            path,
            std.os.linux.IN.MODIFY | std.os.linux.IN.CREATE | std.os.linux.IN.DELETE,
        );

        const path_copy = try self.allocator.dupe(u8, path);
        try self.watch_descriptors.put(wd, path_copy);
    }

    pub fn watch(self: *LinuxInotifyWatcher, callback: *const fn ([]const []const u8) anyerror!void) !void {
        std.debug.print("👀 Watching for changes (using inotify)...\n", .{});

        var buffer: [4096]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;

        while (true) {
            const n = try std.posix.read(self.inotify_fd, &buffer);
            if (n == 0) break;

            var i: usize = 0;
            var changed_files = std.ArrayList([]const u8).init(self.allocator);
            defer {
                for (changed_files.items) |file| {
                    self.allocator.free(file);
                }
                changed_files.deinit();
            }

            while (i < n) {
                const event = @as(*const std.os.linux.inotify_event, @ptrCast(@alignCast(&buffer[i])));
                i += @sizeOf(std.os.linux.inotify_event) + event.len;

                if (self.watch_descriptors.get(event.wd)) |base_path| {
                    const file_name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&buffer[i - event.len])), 0);
                    const full_path = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}/{s}",
                        .{ base_path, file_name },
                    );
                    try changed_files.append(full_path);
                }
            }

            if (changed_files.items.len > 0) {
                try callback(changed_files.items);
            }
        }
    }
};

/// macOS FSEvents-based watcher (stub - would need CoreFoundation bindings)
const MacOSFSEventsWatcher = struct {
    watcher: FileWatcher,

    pub fn init(allocator: std.mem.Allocator) MacOSFSEventsWatcher {
        return .{
            .watcher = FileWatcher.init(allocator),
        };
    }

    pub fn deinit(self: *MacOSFSEventsWatcher) void {
        self.watcher.deinit();
    }

    pub fn addPath(self: *MacOSFSEventsWatcher, path: []const u8) !void {
        try self.watcher.addPath(path);
    }

    pub fn watch(self: *MacOSFSEventsWatcher, callback: *const fn ([]const []const u8) anyerror!void) !void {
        // TODO: Implement FSEvents API
        // For now, fall back to polling
        try self.watcher.watch(callback);
    }
};

/// Windows ReadDirectoryChangesW-based watcher (stub)
const WindowsReadDirectoryChangesWatcher = struct {
    watcher: FileWatcher,

    pub fn init(allocator: std.mem.Allocator) WindowsReadDirectoryChangesWatcher {
        return .{
            .watcher = FileWatcher.init(allocator),
        };
    }

    pub fn deinit(self: *WindowsReadDirectoryChangesWatcher) void {
        self.watcher.deinit();
    }

    pub fn addPath(self: *WindowsReadDirectoryChangesWatcher, path: []const u8) !void {
        try self.watcher.addPath(path);
    }

    pub fn watch(self: *WindowsReadDirectoryChangesWatcher, callback: *const fn ([]const []const u8) anyerror!void) !void {
        // TODO: Implement ReadDirectoryChangesW
        // For now, fall back to polling
        try self.watcher.watch(callback);
    }
};

test "file watcher init" {
    const allocator = std.testing.allocator;

    var watcher = FileWatcher.init(allocator);
    defer watcher.deinit();

    try std.testing.expect(watcher.watched_paths.items.len == 0);
}
