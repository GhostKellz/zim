const std = @import("std");

/// Build.zig.zon dependency entry
pub const ZonDependency = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,

    pub fn deinit(self: *ZonDependency, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.url);
        allocator.free(self.hash);
    }
};

/// Parse build.zig.zon file
pub fn parseBuildZon(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(ZonDependency) {
    var deps = std.ArrayList(ZonDependency).initCapacity(allocator, 0) catch return error.OutOfMemory;
    errdefer {
        for (deps.items) |*dep| dep.deinit(allocator);
        deps.deinit(allocator);
    }

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return deps; // Return empty list if no file
        }
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    const content = try allocator.alloc(u8, stat.size);
    defer allocator.free(content);

    var total_read: usize = 0;
    while (total_read < content.len) {
        const bytes_read = try file.read(content[total_read..]);
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }

    // Parse .dependencies section
    // Look for patterns like: .name = .{ .url = "...", .hash = "..." }
    var lines = std.mem.splitScalar(u8, content, '\n');
    var in_dependencies = false;
    var current_dep_name: ?[]const u8 = null;
    var current_url: ?[]const u8 = null;
    var current_hash: ?[]const u8 = null;

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        // Check if we're entering dependencies section
        if (std.mem.indexOf(u8, trimmed, ".dependencies = .{")) |_| {
            in_dependencies = true;
            continue;
        }

        // Check if we're exiting dependencies section
        if (in_dependencies and std.mem.startsWith(u8, trimmed, "},")) {
            in_dependencies = false;
            continue;
        }

        if (!in_dependencies) continue;

        // Parse dependency name: .zsync = .{
        if (std.mem.startsWith(u8, trimmed, ".")) {
            if (std.mem.indexOf(u8, trimmed, " = .{")) |eq_idx| {
                const name_start = 1; // Skip leading '.'
                const name = trimmed[name_start..eq_idx];
                current_dep_name = name;
                continue;
            }
        }

        // Parse URL: .url = "https://..."
        if (std.mem.indexOf(u8, trimmed, ".url = \"")) |_| {
            if (extractQuotedString(trimmed)) |url| {
                current_url = url;
            }
        }

        // Parse hash: .hash = "1220..."
        if (std.mem.indexOf(u8, trimmed, ".hash = \"")) |_| {
            if (extractQuotedString(trimmed)) |hash| {
                current_hash = hash;
            }
        }

        // Check if we completed a dependency entry
        if (current_dep_name != null and current_url != null and current_hash != null) {
            try deps.append(allocator, .{
                .name = try allocator.dupe(u8, current_dep_name.?),
                .url = try allocator.dupe(u8, current_url.?),
                .hash = try allocator.dupe(u8, current_hash.?),
            });
            current_dep_name = null;
            current_url = null;
            current_hash = null;
        }
    }

    // Check for any remaining dependency at the end of the file
    if (current_dep_name != null and current_url != null and current_hash != null) {
        try deps.append(allocator, .{
            .name = try allocator.dupe(u8, current_dep_name.?),
            .url = try allocator.dupe(u8, current_url.?),
            .hash = try allocator.dupe(u8, current_hash.?),
        });
    }

    return deps;
}

/// Write build.zig.zon file
pub fn writeBuildZon(
    allocator: std.mem.Allocator,
    path: []const u8,
    project_name: []const u8,
    version: []const u8,
    deps: []const ZonDependency,
) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    // Build the content using std.fmt
    const header = try std.fmt.allocPrint(allocator,
        \\.{{
        \\    .name = "{s}",
        \\    .version = "{s}",
        \\    .minimum_zig_version = "0.16.0",
        \\
        \\    .dependencies = .{{
        \\
    , .{ project_name, version });
    defer allocator.free(header);

    try file.writeAll(header);

    // Write dependencies
    for (deps) |dep| {
        const dep_str = try std.fmt.allocPrint(allocator,
            \\        .{s} = .{{
            \\            .url = "{s}",
            \\            .hash = "{s}",
            \\        }},
            \\
        , .{ dep.name, dep.url, dep.hash });
        defer allocator.free(dep_str);
        try file.writeAll(dep_str);
    }

    // Write footer
    try file.writeAll(
        \\    },
        \\
        \\    .paths = .{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\    },
        \\}
        \\
    );
}

fn extractQuotedString(line: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, "\"") orelse return null;
    const end = std.mem.lastIndexOf(u8, line, "\"") orelse return null;
    if (start >= end) return null;
    return line[start + 1 .. end];
}

test "extract quoted string" {
    const result = extractQuotedString("    .url = \"https://example.com\",");
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("https://example.com", result.?);
}
