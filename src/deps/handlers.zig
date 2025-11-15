const std = @import("std");
const deps_mod = @import("deps.zig");
const git_mod = @import("../util/git.zig");
const download_mod = @import("../util/download.zig");
const color = @import("../util/color.zig");
const zcrypto = @import("zcrypto");
const zpack = @import("zpack");

const Dependency = deps_mod.Dependency;
const DependencySource = deps_mod.DependencySource;

/// Result of a dependency fetch operation
pub const FetchResult = struct {
    path: []const u8, // Where the dependency was fetched to
    hash: []const u8, // Content hash of the dependency
    commit: ?[]const u8 = null, // Git commit hash if applicable

    pub fn deinit(self: *FetchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.hash);
        if (self.commit) |c| allocator.free(c);
    }
};

/// Handler for Git dependencies
pub const GitHandler = struct {
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, temp_dir: []const u8) GitHandler {
        return .{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }

    pub fn fetch(self: *GitHandler, name: []const u8, url: []const u8, ref: []const u8) !FetchResult {
        color.info("📦 Fetching Git dependency: {s}\n", .{name});
        color.dim("   URL: {s}\n", .{url});
        color.dim("   Ref: {s}\n", .{ref});

        // Create temporary directory for cloning
        const clone_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.temp_dir, name },
        );
        errdefer self.allocator.free(clone_path);

        // Ensure temp directory exists
        std.fs.makeDirAbsolute(self.temp_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Clone repository
        git_mod.clone(self.allocator, url, clone_path, ref) catch |err| {
            self.allocator.free(clone_path);
            return err;
        };

        // Get commit hash
        const commit = try git_mod.getCurrentCommit(self.allocator, clone_path);
        errdefer self.allocator.free(commit);

        // Compute content hash of the repository
        const content_hash = try self.computeRepoHash(clone_path);
        errdefer self.allocator.free(content_hash);

        color.success("✓ Git dependency fetched\n", .{});
        color.dim("   Commit: {s}\n", .{commit[0..8]});
        color.dim("   Hash: {s}\n", .{content_hash[0..16]});

        return FetchResult{
            .path = clone_path,
            .hash = content_hash,
            .commit = commit,
        };
    }

    fn computeRepoHash(self: *GitHandler, repo_path: []const u8) ![]const u8 {
        // For now, use git rev-parse as the content hash
        // In a production system, you'd want to hash the actual tree content
        const commit = try git_mod.getCurrentCommit(self.allocator, repo_path);
        return commit;
    }
};

/// Handler for tarball dependencies (HTTPS downloads)
pub const TarballHandler = struct {
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, temp_dir: []const u8) TarballHandler {
        return .{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }

    pub fn fetch(self: *TarballHandler, name: []const u8, url: []const u8, expected_hash: []const u8) !FetchResult {
        color.info("📦 Fetching tarball dependency: {s}\n", .{name});
        color.dim("   URL: {s}\n", .{url});
        color.dim("   Expected hash: {s}\n", .{expected_hash[0..16]});

        // Ensure temp directory exists
        std.fs.makeDirAbsolute(self.temp_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Determine file extension from URL
        const archive_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}.tar.gz",
            .{name},
        );
        defer self.allocator.free(archive_name);

        const archive_path = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.temp_dir, archive_name },
        );
        defer self.allocator.free(archive_path);

        // Download tarball with hash verification
        download_mod.downloadFileVerified(
            self.allocator,
            url,
            archive_path,
            expected_hash,
        ) catch |err| {
            color.error_("✗ Download failed: {}\n", .{err});
            return err;
        };

        // Extract to a directory
        const extract_dir = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.temp_dir, name },
        );
        errdefer self.allocator.free(extract_dir);

        // Create extraction directory
        std.fs.makeDirAbsolute(extract_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Extract tarball
        try self.extractArchive(archive_path, extract_dir);

        // Clean up archive
        std.fs.deleteFileAbsolute(archive_path) catch {};

        // Hash is already verified
        const hash_copy = try self.allocator.dupe(u8, expected_hash);
        errdefer self.allocator.free(hash_copy);

        color.success("✓ Tarball dependency fetched and extracted\n", .{});

        return FetchResult{
            .path = extract_dir,
            .hash = hash_copy,
        };
    }

    fn extractArchive(self: *TarballHandler, archive_path: []const u8, output_dir: []const u8) !void {
        // Detect archive type by extension
        if (std.mem.endsWith(u8, archive_path, ".tar.xz") or
            std.mem.endsWith(u8, archive_path, ".txz"))
        {
            return download_mod.extractTarXz(self.allocator, archive_path, output_dir);
        } else if (std.mem.endsWith(u8, archive_path, ".tar.gz") or
            std.mem.endsWith(u8, archive_path, ".tgz"))
        {
            return self.extractTarGz(archive_path, output_dir);
        } else {
            color.warning("⚠ Unknown archive format, trying tar auto-detect\n", .{});
            return self.extractTarGz(archive_path, output_dir);
        }
    }

    fn extractTarGz(self: *TarballHandler, archive_path: []const u8, output_dir: []const u8) !void {
        // Shell out to tar for now
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "tar",
                "-xzf",
                archive_path,
                "-C",
                output_dir,
                "--strip-components=1", // Remove top-level directory
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            color.error_("tar extraction failed: {s}\n", .{result.stderr});
            return error.ExtractionFailed;
        }
    }
};

/// Handler for local path dependencies
pub const LocalHandler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LocalHandler {
        return .{
            .allocator = allocator,
        };
    }

    pub fn fetch(self: *LocalHandler, name: []const u8, path: []const u8) !FetchResult {
        color.info("📦 Using local dependency: {s}\n", .{name});
        color.dim("   Path: {s}\n", .{path});

        // Verify path exists
        var dir = std.fs.openDirAbsolute(path, .{}) catch |err| {
            color.error_("✗ Local path does not exist: {s}\n", .{path});
            return err;
        };
        dir.close();

        // Compute hash of local directory
        const hash = try self.computeDirectoryHash(path);
        errdefer self.allocator.free(hash);

        // For local paths, we don't copy - just reference in place
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        color.success("✓ Local dependency verified\n", .{});
        color.dim("   Hash: {s}\n", .{hash[0..16]});

        return FetchResult{
            .path = path_copy,
            .hash = hash,
        };
    }

    fn computeDirectoryHash(self: *LocalHandler, dir_path: []const u8) ![]const u8 {
        // For simplicity, compute a hash based on directory path and modification time
        // In production, you'd want to hash the actual content
        var hasher = zcrypto.hash.Sha256.init();

        // Hash the path
        hasher.update(dir_path);

        // Get directory stat
        var dir = try std.fs.openDirAbsolute(dir_path, .{});
        defer dir.close();

        const stat = try dir.stat();

        // Hash modification time
        const mtime_bytes = std.mem.asBytes(&stat.mtime);
        hasher.update(mtime_bytes);

        const digest = hasher.final();

        // Convert to hex
        const hex_chars = "0123456789abcdef";
        var hex_buf: [64]u8 = undefined;
        for (digest, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
        }

        return self.allocator.dupe(u8, &hex_buf);
    }
};

/// Unified dependency fetcher that routes to appropriate handler
pub const DependencyFetcher = struct {
    allocator: std.mem.Allocator,
    git_handler: GitHandler,
    tarball_handler: TarballHandler,
    local_handler: LocalHandler,

    pub fn init(allocator: std.mem.Allocator, temp_dir: []const u8) DependencyFetcher {
        return .{
            .allocator = allocator,
            .git_handler = GitHandler.init(allocator, temp_dir),
            .tarball_handler = TarballHandler.init(allocator, temp_dir),
            .local_handler = LocalHandler.init(allocator),
        };
    }

    pub fn fetch(self: *DependencyFetcher, dep: Dependency) !FetchResult {
        return switch (dep.source) {
            .git => |git| self.git_handler.fetch(dep.name, git.url, git.ref),
            .tarball => |tar| self.tarball_handler.fetch(dep.name, tar.url, tar.hash),
            .local => |local| self.local_handler.fetch(dep.name, local.path),
            .registry => |_| {
                color.error_("✗ Registry dependencies not yet implemented\n", .{});
                return error.NotImplemented;
            },
            .github => |gh| {
                // Convert GitHub shorthand to git URL
                const github_mod = @import("github.zig");
                var gh_repo = github_mod.GitHubRepo{
                    .owner = gh.owner,
                    .repo = gh.repo,
                    .ref = gh.ref,
                };
                const git_url = try github_mod.toGitUrl(self.allocator, &gh_repo);
                defer self.allocator.free(git_url);

                const ref = gh.ref orelse "main";
                return self.git_handler.fetch(dep.name, git_url, ref);
            },
        };
    }
};

test "handlers" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
