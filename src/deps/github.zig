const std = @import("std");
const color = @import("../util/color.zig");

/// GitHub repository reference
pub const GitHubRepo = struct {
    owner: []const u8,
    repo: []const u8,
    ref: ?[]const u8 = null, // tag, branch, or commit

    pub fn deinit(self: *GitHubRepo, allocator: std.mem.Allocator) void {
        allocator.free(self.owner);
        allocator.free(self.repo);
        if (self.ref) |r| allocator.free(r);
    }
};

/// Parse GitHub shorthand syntax: gh/owner/repo[@ref]
/// Examples:
///   - gh/ziglang/zig
///   - gh/ziglang/zig@0.11.0
///   - gh/hendriknielaender/zpack@main
pub fn parseGitHubShorthand(allocator: std.mem.Allocator, shorthand: []const u8) !GitHubRepo {
    // Must start with "gh/"
    if (!std.mem.startsWith(u8, shorthand, "gh/")) {
        return error.InvalidGitHubShorthand;
    }

    const rest = shorthand[3..]; // Skip "gh/"

    // Split by @  to separate repo from ref
    var ref_split = std.mem.splitSequence(u8, rest, "@");
    const repo_part = ref_split.first();
    const ref_part = ref_split.next();

    // Split repo_part by / to get owner and repo
    var repo_split = std.mem.splitSequence(u8, repo_part, "/");
    const owner = repo_split.next() orelse return error.InvalidGitHubShorthand;
    const repo = repo_split.next() orelse return error.InvalidGitHubShorthand;

    // Ensure no extra slashes
    if (repo_split.next() != null) return error.InvalidGitHubShorthand;

    return GitHubRepo{
        .owner = try allocator.dupe(u8, owner),
        .repo = try allocator.dupe(u8, repo),
        .ref = if (ref_part) |r| try allocator.dupe(u8, r) else null,
    };
}

/// Convert GitHub shorthand to full git URL
pub fn toGitUrl(allocator: std.mem.Allocator, gh_repo: *const GitHubRepo) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/{s}/{s}.git",
        .{ gh_repo.owner, gh_repo.repo },
    );
}

/// Convert GitHub shorthand to tarball URL for a specific ref
pub fn toTarballUrl(allocator: std.mem.Allocator, gh_repo: *const GitHubRepo) ![]const u8 {
    const ref = gh_repo.ref orelse "main";
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/{s}/{s}/archive/refs/tags/{s}.tar.gz",
        .{ gh_repo.owner, gh_repo.repo, ref },
    );
}

/// Get release tarball URL
pub fn toReleaseUrl(allocator: std.mem.Allocator, gh_repo: *const GitHubRepo) ![]const u8 {
    const ref = gh_repo.ref orelse return error.MissingRef;
    return std.fmt.allocPrint(
        allocator,
        "https://github.com/{s}/{s}/releases/download/{s}/{s}-{s}.tar.gz",
        .{ gh_repo.owner, gh_repo.repo, ref, gh_repo.repo, ref },
    );
}

/// Fetch repository information using GitHub API
pub fn fetchRepoInfo(allocator: std.mem.Allocator, gh_repo: *const GitHubRepo) !RepoInfo {
    const api_url = try std.fmt.allocPrint(
        allocator,
        "https://api.github.com/repos/{s}/{s}",
        .{ gh_repo.owner, gh_repo.repo },
    );
    defer allocator.free(api_url);

    // Use curl to fetch the data
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "-s", "-H", "Accept: application/vnd.github+json", api_url },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitHubApiFailed;
    }

    // Parse JSON response
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value.object;

    const description = if (root.get("description")) |desc|
        if (desc != .null) try allocator.dupe(u8, desc.string) else null
    else
        null;

    const default_branch = if (root.get("default_branch")) |branch|
        try allocator.dupe(u8, branch.string)
    else
        null;

    const stars = if (root.get("stargazers_count")) |count| @as(u32, @intCast(count.integer)) else 0;

    return RepoInfo{
        .description = description,
        .default_branch = default_branch,
        .stars = stars,
    };
}

/// Repository information from GitHub API
pub const RepoInfo = struct {
    description: ?[]const u8 = null,
    default_branch: ?[]const u8 = null,
    stars: u32 = 0,

    pub fn deinit(self: *RepoInfo, allocator: std.mem.Allocator) void {
        if (self.description) |desc| allocator.free(desc);
        if (self.default_branch) |branch| allocator.free(branch);
    }

    pub fn print(self: *const RepoInfo) void {
        if (self.description) |desc| {
            color.dim("  {s}\n", .{desc});
        }
        if (self.default_branch) |branch| {
            color.dim("  Default branch: {s}\n", .{branch});
        }
        color.dim("  ⭐ {d} stars\n", .{self.stars});
    }
};

/// Fetch latest release tag
pub fn fetchLatestRelease(allocator: std.mem.Allocator, gh_repo: *const GitHubRepo) ![]const u8 {
    const api_url = try std.fmt.allocPrint(
        allocator,
        "https://api.github.com/repos/{s}/{s}/releases/latest",
        .{ gh_repo.owner, gh_repo.repo },
    );
    defer allocator.free(api_url);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "curl", "-s", "-H", "Accept: application/vnd.github+json", api_url },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitHubApiFailed;
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, result.stdout, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const tag_name = root.get("tag_name") orelse return error.NoRelease;

    return allocator.dupe(u8, tag_name.string);
}

// Tests
test "parse GitHub shorthand" {
    const allocator = std.testing.allocator;

    // Basic format
    {
        var gh = try parseGitHubShorthand(allocator, "gh/ziglang/zig");
        defer gh.deinit(allocator);

        try std.testing.expectEqualStrings("ziglang", gh.owner);
        try std.testing.expectEqualStrings("zig", gh.repo);
        try std.testing.expect(gh.ref == null);
    }

    // With ref
    {
        var gh = try parseGitHubShorthand(allocator, "gh/ziglang/zig@0.11.0");
        defer gh.deinit(allocator);

        try std.testing.expectEqualStrings("ziglang", gh.owner);
        try std.testing.expectEqualStrings("zig", gh.repo);
        try std.testing.expect(gh.ref != null);
        try std.testing.expectEqualStrings("0.11.0", gh.ref.?);
    }

    // Invalid format
    {
        const result = parseGitHubShorthand(allocator, "ziglang/zig");
        try std.testing.expectError(error.InvalidGitHubShorthand, result);
    }
}

test "convert to URLs" {
    const allocator = std.testing.allocator;

    var gh = try parseGitHubShorthand(allocator, "gh/hendriknielaender/zpack@v0.3.3");
    defer gh.deinit(allocator);

    const git_url = try toGitUrl(allocator, &gh);
    defer allocator.free(git_url);
    try std.testing.expectEqualStrings("https://github.com/hendriknielaender/zpack.git", git_url);

    const tarball_url = try toTarballUrl(allocator, &gh);
    defer allocator.free(tarball_url);
    try std.testing.expectEqualStrings("https://github.com/hendriknielaender/zpack/archive/refs/tags/v0.3.3.tar.gz", tarball_url);
}
