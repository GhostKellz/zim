const std = @import("std");
const builtin = @import("builtin");
const color = @import("color.zig");
const download_mod = @import("download.zig");

/// ZIM update information
pub const UpdateInfo = struct {
    current_version: []const u8,
    latest_version: []const u8,
    download_url: []const u8,
    is_newer: bool,

    pub fn deinit(self: *UpdateInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.current_version);
        allocator.free(self.latest_version);
        allocator.free(self.download_url);
    }
};

/// Check for updates
pub fn checkForUpdates(allocator: std.mem.Allocator, current_version: []const u8) !UpdateInfo {
    color.info("Checking for updates...\n", .{});

    // Fetch latest release from GitHub
    const api_url = "https://api.github.com/repos/hendriknielaender/zim/releases/latest";

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "-s", "-H", "Accept: application/vnd.github+json", api_url },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.UpdateCheckFailed;
    }

    // Parse JSON response
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const tag_name_value = root.get("tag_name") orelse return error.NoRelease;
    const tag_name = tag_name_value.string;

    // Find asset for current platform
    const assets = root.get("assets") orelse return error.NoAssets;
    const asset_url = try findPlatformAsset(allocator, assets.array);

    // Compare versions
    const is_newer = try compareVersions(current_version, tag_name);

    return UpdateInfo{
        .current_version = try allocator.dupe(u8, current_version),
        .latest_version = try allocator.dupe(u8, tag_name),
        .download_url = asset_url,
        .is_newer = is_newer,
    };
}

/// Find the appropriate asset for the current platform
fn findPlatformAsset(allocator: std.mem.Allocator, assets: std.json.Array) ![]const u8 {
    const os_tag = switch (builtin.os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => return error.UnsupportedPlatform,
    };

    const arch_tag = switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "aarch64",
        else => return error.UnsupportedArchitecture,
    };

    // Look for matching asset
    for (assets.items) |asset| {
        const asset_obj = asset.object;
        const name_value = asset_obj.get("name") orelse continue;
        const name = name_value.string;

        // Match pattern like: zim-linux-x86_64
        if (std.mem.indexOf(u8, name, os_tag) != null and
            std.mem.indexOf(u8, name, arch_tag) != null)
        {
            const url_value = asset_obj.get("browser_download_url") orelse continue;
            return allocator.dupe(u8, url_value.string);
        }
    }

    return error.NoMatchingAsset;
}

/// Compare semantic versions (simple implementation)
fn compareVersions(current: []const u8, latest: []const u8) !bool {
    // Strip 'v' prefix if present
    const curr_clean = if (std.mem.startsWith(u8, current, "v")) current[1..] else current;
    const latest_clean = if (std.mem.startsWith(u8, latest, "v")) latest[1..] else latest;

    // Simple string comparison for now
    // TODO: Use proper semver comparison
    return !std.mem.eql(u8, curr_clean, latest_clean);
}

/// Perform self-update
pub fn performUpdate(allocator: std.mem.Allocator, update_info: *const UpdateInfo) !void {
    color.info("\nDownloading ZIM {s}...\n", .{update_info.latest_version});

    // Get current executable path
    const exe_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(exe_path);

    // Download new version to temporary file
    const temp_path = try std.fmt.allocPrint(allocator, "{s}.new", .{exe_path});
    defer allocator.free(temp_path);

    // Download the update
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "-L", "-o", temp_path, update_info.download_url },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.DownloadFailed;
    }

    // Make the new binary executable
    const chmod_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "chmod", "+x", temp_path },
    });
    defer allocator.free(chmod_result.stdout);
    defer allocator.free(chmod_result.stderr);

    // Backup current version
    const backup_path = try std.fmt.allocPrint(allocator, "{s}.backup", .{exe_path});
    defer allocator.free(backup_path);

    std.fs.renameAbsolute(exe_path, backup_path) catch |err| {
        color.error_("Failed to backup current version: {}\n", .{err});
        return error.BackupFailed;
    };

    // Move new version to executable path
    std.fs.renameAbsolute(temp_path, exe_path) catch |err| {
        color.error_("Failed to install new version: {}\n", .{err});
        // Restore backup
        std.fs.renameAbsolute(backup_path, exe_path) catch {};
        return error.InstallFailed;
    };

    // Remove backup
    std.fs.deleteFileAbsolute(backup_path) catch {};

    color.success("\n✓ Successfully updated to ZIM {s}!\n", .{update_info.latest_version});
    color.dim("  Please restart ZIM to use the new version.\n", .{});
}

/// Interactive update check and prompt
pub fn interactiveUpdate(allocator: std.mem.Allocator, current_version: []const u8) !void {
    var update_info = try checkForUpdates(allocator, current_version);
    defer update_info.deinit(allocator);

    if (!update_info.is_newer) {
        color.success("✓ You are running the latest version ({s})\n", .{current_version});
        return;
    }

    color.warning("\n⚠ Update available!\n", .{});
    color.dim("  Current: {s}\n", .{update_info.current_version});
    color.info("  Latest:  {s}\n", .{update_info.latest_version});

    // Prompt user
    color.dim("\nUpdate now? [Y/n]: ", .{});

    // For now, just auto-update without prompting
    // TODO: Add proper stdin reading when implementing interactive mode
    const response = "y";
    const trimmed = std.mem.trim(u8, response, &std.ascii.whitespace);

    if (trimmed.len == 0 or std.ascii.toLower(trimmed[0]) == 'y') {
        try performUpdate(allocator, &update_info);
    } else {
        color.dim("Update cancelled.\n", .{});
    }
}
