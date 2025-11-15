const std = @import("std");

/// Clone a git repository
pub fn clone(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    ref: ?[]const u8,
) !void {
    std.debug.print("Cloning git repository: {s}\n", .{url});

    // Build git clone command
    var argv = try std.ArrayList([]const u8).initCapacity(allocator, 8);
    defer argv.deinit(allocator);

    try argv.append(allocator, "git");
    try argv.append(allocator, "clone");
    try argv.append(allocator, "--depth");
    try argv.append(allocator, "1"); // Shallow clone for speed

    if (ref) |r| {
        try argv.append(allocator, "--branch");
        try argv.append(allocator, r);
    }

    try argv.append(allocator, url);
    try argv.append(allocator, dest_path);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("Git clone failed (exit {d}): {s}\n", .{ code, result.stderr });
                return error.GitCloneFailed;
            }
        },
        else => {
            std.debug.print("Git clone failed: {s}\n", .{result.stderr});
            return error.GitCloneFailed;
        },
    }

    std.debug.print("✓ Cloned successfully\n", .{});
}

/// Get the current commit hash of a git repository
pub fn getCurrentCommit(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
) ![]const u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "git",
            "-C",
            repo_path,
            "rev-parse",
            "HEAD",
        },
    });
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return error.GitRevParseFailed;
            }
        },
        else => {
            allocator.free(result.stdout);
            return error.GitRevParseFailed;
        },
    }

    // Trim newline
    const commit = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
    const commit_copy = try allocator.dupe(u8, commit);
    allocator.free(result.stdout);

    return commit_copy;
}

/// Fetch updates from remote
pub fn fetch(allocator: std.mem.Allocator, repo_path: []const u8) !void {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "git",
            "-C",
            repo_path,
            "fetch",
            "--depth",
            "1",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                return error.GitFetchFailed;
            }
        },
        else => return error.GitFetchFailed,
    }
}

/// Check if a directory is a git repository
pub fn isGitRepo(path: []const u8) bool {
    const git_dir = std.fs.path.join(
        std.heap.page_allocator,
        &[_][]const u8{ path, ".git" },
    ) catch return false;
    defer std.heap.page_allocator.free(git_dir);

    var dir = std.fs.openDirAbsolute(git_dir, .{}) catch return false;
    dir.close();
    return true;
}
