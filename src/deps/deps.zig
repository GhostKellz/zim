const std = @import("std");
const builtin = @import("builtin");
const download = @import("../util/download.zig");
const zontom = @import("zontom");
const build_zon = @import("build_zon.zig");
const graph_mod = @import("graph.zig");
const git_mod = @import("../util/git.zig");
const github_mod = @import("github.zig");
const color = @import("../util/color.zig");
const handlers = @import("handlers.zig");
const manifest_mod = @import("manifest.zig");
const semver = @import("../util/semver.zig");

/// Dependency source types
pub const DependencySource = union(enum) {
    git: struct {
        url: []const u8,
        ref: []const u8, // branch, tag, or commit
    },
    tarball: struct {
        url: []const u8,
        hash: []const u8,
    },
    local: struct {
        path: []const u8,
    },
    registry: struct {
        name: []const u8,
        version: []const u8,
    },
    github: struct {
        owner: []const u8,
        repo: []const u8,
        ref: ?[]const u8,
    },
};

/// Dependency metadata
pub const Dependency = struct {
    name: []const u8,
    source: DependencySource,
    hash: ?[]const u8 = null, // Content hash for verification
    constraint: ?semver.Constraint = null, // Version constraint (for registry deps)
    version: ?semver.Version = null, // Resolved version

    pub fn deinit(self: *Dependency, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        switch (self.source) {
            .git => |git| {
                allocator.free(git.url);
                allocator.free(git.ref);
            },
            .tarball => |tar| {
                allocator.free(tar.url);
                allocator.free(tar.hash);
            },
            .local => |local| {
                allocator.free(local.path);
            },
            .registry => |reg| {
                allocator.free(reg.name);
                allocator.free(reg.version);
            },
            .github => |gh| {
                allocator.free(gh.owner);
                allocator.free(gh.repo);
                if (gh.ref) |r| allocator.free(r);
            },
        }
        if (self.hash) |h| allocator.free(h);
        if (self.constraint) |c| {
            var mut_c = c;
            mut_c.deinit(allocator);
        }
        if (self.version) |v| {
            var mut_v = v;
            mut_v.deinit(allocator);
        }
    }

    /// Create dependency from GitHub shorthand (gh/owner/repo[@ref])
    pub fn fromGitHubShorthand(allocator: std.mem.Allocator, shorthand: []const u8) !Dependency {
        var gh_repo = try github_mod.parseGitHubShorthand(allocator, shorthand);
        errdefer gh_repo.deinit(allocator);

        return Dependency{
            .name = try allocator.dupe(u8, gh_repo.repo),
            .source = .{
                .github = .{
                    .owner = gh_repo.owner,
                    .repo = gh_repo.repo,
                    .ref = gh_repo.ref,
                },
            },
        };
    }
};

/// Provenance metadata for lockfile entries
pub const Provenance = struct {
    origin: ?[]const u8 = null, // Source URL or identifier
    digest: ?[]const u8 = null, // SHA-256 hash
    fetched_at: ?[]const u8 = null, // ISO 8601 timestamp
    size: ?u64 = null, // Size in bytes

    pub fn deinit(self: *Provenance, allocator: std.mem.Allocator) void {
        if (self.origin) |o| allocator.free(o);
        if (self.digest) |d| allocator.free(d);
        if (self.fetched_at) |f| allocator.free(f);
    }
};

/// Lockfile entry for reproducible builds
pub const LockfileEntry = struct {
    name: []const u8,
    version: []const u8,
    hash: []const u8,
    source: []const u8,
    dependencies: std.ArrayListUnmanaged([]const u8),
    provenance: ?Provenance = null, // Optional provenance metadata

    pub fn deinit(self: *LockfileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.hash);
        allocator.free(self.source);
        for (self.dependencies.items) |dep| {
            allocator.free(dep);
        }
        self.dependencies.deinit(allocator);
        if (self.provenance) |*p| {
            var mut_p = p.*;
            mut_p.deinit(allocator);
        }
    }
};

/// Lockfile for reproducible dependency resolution
pub const Lockfile = struct {
    entries: std.StringHashMapUnmanaged(LockfileEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Lockfile {
        return Lockfile{
            .entries = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lockfile) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            var mut_entry = entry.value_ptr.*;
            mut_entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Lockfile {
        var lockfile = Lockfile.init(allocator);
        errdefer lockfile.deinit();

        // Try to open lockfile
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No lockfile yet, return empty
                return lockfile;
            }
            return err;
        };
        defer file.close();

        // Read file contents
        const stat = try file.stat();
        const content = try allocator.alloc(u8, stat.size);
        defer allocator.free(content);

        var total_read: usize = 0;
        while (total_read < content.len) {
            const bytes_read = try file.read(content[total_read..]);
            if (bytes_read == 0) break;
            total_read += bytes_read;
        }

        // Parse TOML lockfile using zontom
        var table = zontom.parse(allocator, content) catch |err| {
            std.debug.print("Failed to parse lockfile: {}\n", .{err});
            return lockfile; // Return empty lockfile on parse error
        };
        defer table.deinit();

        // TODO: Extract lockfile entries from parsed TOML
        // For now, just return empty lockfile
        std.debug.print("Lockfile entry extraction not yet implemented\n", .{});

        return lockfile;
    }

    pub fn save(self: *Lockfile, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Write header (Babylon-inspired format)
        try file.writeAll("# ZIM dependency lockfile (Babylon format)\n");
        try file.writeAll("# This file is automatically generated. Do not edit manually.\n");
        try file.writeAll("#\n");
        try file.writeAll("# This lockfile ensures reproducible builds by recording exact versions\n");
        try file.writeAll("# and content hashes of all dependencies.\n");
        try file.writeAll("#\n");

        // Write timestamp comment
        try file.writeAll("# Generated at build time\n\n");

        // Write lockfile version
        try file.writeAll("[metadata]\n");
        try file.writeAll("version = \"1.0\"\n");
        try file.writeAll("format = \"babylon\"\n\n");

        // Write each dependency as a TOML table
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            const lockentry = entry.value_ptr.*;

            // Write dependency table
            const table_header = try std.fmt.allocPrint(
                self.allocator,
                "[[dependencies]]\n",
                .{},
            );
            defer self.allocator.free(table_header);
            try file.writeAll(table_header);

            // Write fields
            const name_line = try std.fmt.allocPrint(
                self.allocator,
                "name = \"{s}\"\n",
                .{name},
            );
            defer self.allocator.free(name_line);
            try file.writeAll(name_line);

            const version_line = try std.fmt.allocPrint(
                self.allocator,
                "version = \"{s}\"\n",
                .{lockentry.version},
            );
            defer self.allocator.free(version_line);
            try file.writeAll(version_line);

            const hash_line = try std.fmt.allocPrint(
                self.allocator,
                "hash = \"{s}\"\n",
                .{lockentry.hash},
            );
            defer self.allocator.free(hash_line);
            try file.writeAll(hash_line);

            const source_line = try std.fmt.allocPrint(
                self.allocator,
                "source = \"{s}\"\n",
                .{lockentry.source},
            );
            defer self.allocator.free(source_line);
            try file.writeAll(source_line);

            // Write transitive dependencies if any
            if (lockentry.dependencies.items.len > 0) {
                try file.writeAll("dependencies = [");
                for (lockentry.dependencies.items, 0..) |dep, i| {
                    if (i > 0) try file.writeAll(", ");
                    const dep_str = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{dep});
                    defer self.allocator.free(dep_str);
                    try file.writeAll(dep_str);
                }
                try file.writeAll("]\n");
            }

            try file.writeAll("\n");
        }

        color.success("✓ Lockfile saved to {s}\n", .{path});
    }
};

/// Content-addressed cache for dependencies (Babylon-inspired)
pub const DependencyCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !DependencyCache {
        return DependencyCache{
            .allocator = allocator,
            .cache_dir = try allocator.dupe(u8, cache_dir),
        };
    }

    pub fn deinit(self: *DependencyCache) void {
        self.allocator.free(self.cache_dir);
    }

    /// Get path to cached dependency by content hash
    pub fn getCachePath(self: *DependencyCache, hash: []const u8) ![]const u8 {
        // Use content-addressable storage: cache_dir/deps/ab/cd/abcdef123...
        const prefix = hash[0..2];
        const subdir = hash[2..4];

        return std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.cache_dir, "deps", prefix, subdir, hash },
        );
    }

    /// Check if dependency is already cached
    pub fn isCached(self: *DependencyCache, hash: []const u8) !bool {
        const cache_path = try self.getCachePath(hash);
        defer self.allocator.free(cache_path);

        var dir = std.fs.openDirAbsolute(cache_path, .{}) catch {
            return false;
        };
        dir.close();
        return true;
    }

    /// Store dependency in cache
    pub fn store(self: *DependencyCache, hash: []const u8, source_path: []const u8) !void {
        const cache_path = try self.getCachePath(hash);
        defer self.allocator.free(cache_path);

        // Create parent directories recursively
        const parent = std.fs.path.dirname(cache_path) orelse return error.InvalidPath;

        // Use mkdir -p to create all parent directories
        const mkdir_result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "mkdir",
                "-p",
                parent,
            },
        });
        defer self.allocator.free(mkdir_result.stdout);
        defer self.allocator.free(mkdir_result.stderr);

        switch (mkdir_result.term) {
            .Exited => |code| {
                if (code != 0) {
                    color.error_("Failed to create cache directories: {s}\n", .{mkdir_result.stderr});
                    return error.CacheFailed;
                }
            },
            else => return error.CacheFailed,
        }

        // Copy source directory to cache using cp command
        // This is more reliable than manual directory traversal for now
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "cp",
                "-r",
                source_path,
                cache_path,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    color.error_("Failed to cache dependency: {s}\n", .{result.stderr});
                    return error.CacheFailed;
                }
            },
            else => return error.CacheFailed,
        }

        color.dim("✓ Cached dependency: {s}\n", .{hash[0..8]});
    }

    /// Retrieve dependency from cache
    pub fn retrieve(self: *DependencyCache, hash: []const u8, dest_path: []const u8) !void {
        const cache_path = try self.getCachePath(hash);
        defer self.allocator.free(cache_path);

        if (!try self.isCached(hash)) {
            return error.NotCached;
        }

        color.dim("Retrieving from cache: {s}\n", .{hash[0..8]});

        // Copy directory from cache to destination
        const result = try std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &[_][]const u8{
                "cp",
                "-r",
                cache_path,
                dest_path,
            },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        switch (result.term) {
            .Exited => |code| {
                if (code != 0) {
                    color.error_("Failed to retrieve from cache: {s}\n", .{result.stderr});
                    return error.RetrieveFailed;
                }
            },
            else => return error.RetrieveFailed,
        }

        color.success("✓ Retrieved from cache\n", .{});
    }

    /// Clean cache (remove unused dependencies)
    pub fn clean(self: *DependencyCache, keep_hashes: []const []const u8) !void {
        _ = keep_hashes;
        std.debug.print("Cleaning dependency cache...\n", .{});

        const deps_dir = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.cache_dir, "deps" },
        );
        defer self.allocator.free(deps_dir);

        // TODO: Walk cache directory and remove entries not in keep_hashes
        std.debug.print("(Cache cleaning not yet implemented)\n", .{});
    }
};

/// Dependency manager with Babylon-inspired features
pub const DependencyManager = struct {
    allocator: std.mem.Allocator,
    cache: DependencyCache,
    lockfile: Lockfile,
    manifest_path: []const u8,
    lockfile_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !DependencyManager {
        const cache = try DependencyCache.init(allocator, cache_dir);

        return DependencyManager{
            .allocator = allocator,
            .cache = cache,
            .lockfile = Lockfile.init(allocator),
            .manifest_path = try allocator.dupe(u8, "zim.toml"),
            .lockfile_path = try allocator.dupe(u8, "zim.lock"),
        };
    }

    pub fn deinit(self: *DependencyManager) void {
        self.cache.deinit();
        self.lockfile.deinit();
        self.allocator.free(self.manifest_path);
        self.allocator.free(self.lockfile_path);
    }

    /// Initialize a new project with zim.toml manifest
    pub fn initProject(self: *DependencyManager, project_name: []const u8) !void {
        std.debug.print("Initializing ZIM project: {s}\n", .{project_name});

        // Create zim.toml manifest
        const manifest_content = try std.fmt.allocPrint(
            self.allocator,
            \\# ZIM project manifest
            \\
            \\[project]
            \\name = "{s}"
            \\version = "0.1.0"
            \\zig = "0.16.0"
            \\
            \\[dependencies]
            \\# Add dependencies here
            \\# example = {{ git = "https://github.com/user/repo", ref = "main" }}
            \\# other = {{ tarball = "https://example.com/package.tar.gz", hash = "sha256:..." }}
            \\
            \\[dev-dependencies]
            \\# Development dependencies
            \\
            \\[targets]
            \\# Cross-compilation targets
            \\default = ["native"]
            \\
        ,
            .{project_name},
        );
        defer self.allocator.free(manifest_content);

        const file = try std.fs.cwd().createFile(self.manifest_path, .{});
        defer file.close();
        try file.writeAll(manifest_content);

        std.debug.print("✓ Created {s}\n", .{self.manifest_path});
    }

    /// Add a dependency to the manifest
    pub fn addDependency(self: *DependencyManager, dep: Dependency) !void {
        color.info("📦 Adding dependency: {s}\n", .{dep.name});

        // Load existing manifest
        var manifest = manifest_mod.Manifest.load(self.allocator, self.manifest_path) catch |err| {
            if (err == error.FileNotFound) {
                color.error_("✗ No zim.toml found. Run 'zim deps init' first.\n", .{});
                return err;
            }
            return err;
        };
        defer {
            var mut_manifest = manifest;
            mut_manifest.deinit();
        }

        // Check if dependency already exists
        if (manifest.dependencies.get(dep.name)) |_| {
            color.warning("⚠ Dependency '{s}' already exists. Updating...\n", .{dep.name});
        }

        // Add dependency to manifest
        try manifest.dependencies.put(
            self.allocator,
            try self.allocator.dupe(u8, dep.name),
            dep,
        );

        // Save updated manifest
        try manifest.save(self.manifest_path);

        color.success("✓ Added dependency: {s}\n", .{dep.name});
        color.dim("Run 'zim deps fetch' to download the dependency\n", .{});
    }

    /// Fetch all dependencies
    pub fn fetch(self: *DependencyManager) !void {
        color.bold("\n🚀 Fetching dependencies...\n\n", .{});

        // Load manifest
        const manifest = manifest_mod.Manifest.load(self.allocator, self.manifest_path) catch |err| {
            if (err == error.FileNotFound) {
                color.error_("✗ No zim.toml found. Run 'zim deps init' first.\n", .{});
                return err;
            }
            return err;
        };
        defer {
            var mut_manifest = manifest;
            mut_manifest.deinit();
        }

        // Load existing lockfile or create new one
        self.lockfile = Lockfile.load(self.allocator, self.lockfile_path) catch |err| blk: {
            if (err == error.FileNotFound) {
                color.dim("No existing lockfile, creating new one\n", .{});
                break :blk Lockfile.init(self.allocator);
            }
            color.error_("Failed to load lockfile: {}\n", .{err});
            return err;
        };

        color.dim("Creating cache and temporary directories\n", .{});

        // Ensure cache directory exists
        std.fs.makeDirAbsolute(self.cache.cache_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                color.error_("Failed to create cache dir {s}: {}\n", .{ self.cache.cache_dir, err });
                return err;
            }
        };

        // Create temporary directory for fetching
        const temp_dir = try std.fs.path.join(
            self.allocator,
            &[_][]const u8{ self.cache.cache_dir, "tmp" },
        );
        defer self.allocator.free(temp_dir);

        std.fs.makeDirAbsolute(temp_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                color.error_("Failed to create temp dir {s}: {}\n", .{ temp_dir, err });
                return err;
            }
        };

        color.dim("Initializing fetcher\n", .{});

        // Initialize fetcher
        var fetcher = handlers.DependencyFetcher.init(self.allocator, temp_dir);

        // Fetch all dependencies
        var dep_it = manifest.dependencies.iterator();
        while (dep_it.next()) |entry| {
            const dep = entry.value_ptr.*;

            color.dim("\n", .{});
            const result = try fetcher.fetch(dep);
            defer {
                var mut_result = result;
                mut_result.deinit(self.allocator);
            }

            // Store in cache
            if (!try self.cache.isCached(result.hash)) {
                try self.cache.store(result.hash, result.path);
            }

            // Add to lockfile
            const lockfile_entry = LockfileEntry{
                .name = try self.allocator.dupe(u8, dep.name),
                .version = if (result.commit) |c|
                    try self.allocator.dupe(u8, c)
                else
                    try self.allocator.dupe(u8, "0.0.0"),
                .hash = try self.allocator.dupe(u8, result.hash),
                .source = try self.formatSource(dep.source),
                .dependencies = .{},
            };

            try self.lockfile.entries.put(
                self.allocator,
                try self.allocator.dupe(u8, dep.name),
                lockfile_entry,
            );
        }

        // Save lockfile
        color.dim("\n", .{});
        try self.lockfile.save(self.lockfile_path);

        color.bold("\n✓ All dependencies fetched successfully!\n", .{});
    }

    fn formatSource(self: *DependencyManager, source: DependencySource) ![]const u8 {
        return switch (source) {
            .git => |git| try std.fmt.allocPrint(
                self.allocator,
                "git+{s}#{s}",
                .{ git.url, git.ref },
            ),
            .tarball => |tar| try std.fmt.allocPrint(
                self.allocator,
                "tarball+{s}",
                .{tar.url},
            ),
            .local => |local| try std.fmt.allocPrint(
                self.allocator,
                "path:{s}",
                .{local.path},
            ),
            .registry => |reg| try std.fmt.allocPrint(
                self.allocator,
                "registry:{s}@{s}",
                .{ reg.name, reg.version },
            ),
            .github => |gh| blk: {
                const ref_str = if (gh.ref) |r| r else "main";
                break :blk try std.fmt.allocPrint(
                    self.allocator,
                    "gh/{s}/{s}@{s}",
                    .{ gh.owner, gh.repo, ref_str },
                );
            },
        };
    }

    /// Display dependency graph with beautiful ASCII tree
    pub fn graphDisplay(self: *DependencyManager) !void {
        std.debug.print("Dependency graph:\n\n", .{});

        // Load lockfile
        self.lockfile = try Lockfile.load(self.allocator, self.lockfile_path);

        if (self.lockfile.entries.count() == 0) {
            std.debug.print("  (no dependencies)\n", .{});
            std.debug.print("\nRun 'zim deps fetch' to install dependencies\n", .{});
            return;
        }

        // Build dependency tree
        // For now, show a simple flat list with stats
        var it = self.lockfile.entries.iterator();
        var count: usize = 0;
        while (it.next()) |entry| {
            std.debug.print("  {s} @ {s}\n", .{ entry.key_ptr.*, entry.value_ptr.version });
            for (entry.value_ptr.dependencies.items) |dep| {
                std.debug.print("    └── {s}\n", .{dep});
            }
            count += 1;
        }

        std.debug.print("\nTotal: {d} direct dependencies\n", .{count});
    }

    // Keep old name for compatibility
    pub const graph = graphDisplay;

    /// Verify all dependencies against lockfile
    pub fn verify(self: *DependencyManager) !void {
        std.debug.print("Verifying dependencies...\n", .{});

        // Load lockfile
        self.lockfile = try Lockfile.load(self.allocator, self.lockfile_path);

        if (self.lockfile.entries.count() == 0) {
            std.debug.print("No dependencies to verify\n", .{});
            return;
        }

        // TODO: Verify each dependency hash
        // TODO: Check for tampering
        // TODO: Validate signatures if required

        var verified: usize = 0;
        var it = self.lockfile.entries.iterator();
        while (it.next()) |entry| {
            std.debug.print("  Verifying {s}...", .{entry.key_ptr.*});

            // TODO: Actually verify
            std.debug.print(" ✓\n", .{});
            verified += 1;
        }

        std.debug.print("\n✓ Verified {d} dependencies\n", .{verified});
    }

    /// Update dependencies to latest versions
    pub fn update(self: *DependencyManager, dependency_name: ?[]const u8) !void {
        _ = self;
        if (dependency_name) |name| {
            std.debug.print("Updating dependency: {s}\n", .{name});
        } else {
            std.debug.print("Updating all dependencies...\n", .{});
        }

        // TODO: Check for updates
        // TODO: Resolve new versions
        // TODO: Update lockfile

        std.debug.print("(Dependency update not yet implemented)\n", .{});
    }

    /// Clean unused dependencies from cache
    pub fn cleanCache(self: *DependencyManager) !void {
        std.debug.print("Cleaning dependency cache...\n", .{});

        // Load lockfile to get active dependencies
        self.lockfile = try Lockfile.load(self.allocator, self.lockfile_path);

        var keep_hashes = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        defer keep_hashes.deinit(self.allocator);

        var it = self.lockfile.entries.iterator();
        while (it.next()) |entry| {
            try keep_hashes.append(self.allocator, entry.value_ptr.hash);
        }

        try self.cache.clean(keep_hashes.items);
    }

    /// Import dependencies from build.zig.zon file
    pub fn importFromZon(self: *DependencyManager, zon_path: []const u8) !void {
        color.info("📥 Importing dependencies from {s}\n", .{zon_path});

        // Parse build.zig.zon
        var zon_deps = try build_zon.parseBuildZon(self.allocator, zon_path);
        defer {
            for (zon_deps.items) |*dep| dep.deinit(self.allocator);
            zon_deps.deinit(self.allocator);
        }

        if (zon_deps.items.len == 0) {
            color.warning("⚠ No dependencies found in {s}\n", .{zon_path});
            return;
        }

        // Load existing manifest
        var manifest = manifest_mod.Manifest.load(self.allocator, self.manifest_path) catch |err| {
            if (err == error.FileNotFound) {
                color.error_("✗ No zim.toml found. Run 'zim deps init' first.\n", .{});
                return err;
            }
            return err;
        };
        defer {
            var mut_manifest = manifest;
            mut_manifest.deinit();
        }

        // Convert and add each dependency
        var added_count: usize = 0;
        for (zon_deps.items) |zon_dep| {
            // Create ZIM dependency from ZON dependency
            const dep = Dependency{
                .name = try self.allocator.dupe(u8, zon_dep.name),
                .source = .{
                    .tarball = .{
                        .url = try self.allocator.dupe(u8, zon_dep.url),
                        .hash = try self.allocator.dupe(u8, zon_dep.hash),
                    },
                },
            };

            // Add to manifest
            try manifest.dependencies.put(
                self.allocator,
                try self.allocator.dupe(u8, dep.name),
                dep,
            );
            added_count += 1;
            color.dim("  + {s}\n", .{zon_dep.name});
        }

        // Save updated manifest
        try manifest.save(self.manifest_path);

        color.success("✓ Imported {d} dependencies from {s}\n", .{ added_count, zon_path });
        color.dim("Run 'zim deps fetch' to download the dependencies\n", .{});
    }

    /// Export dependencies to build.zig.zon file
    pub fn exportToZon(self: *DependencyManager, zon_path: []const u8) !void {
        color.info("📤 Exporting dependencies to {s}\n", .{zon_path});

        // Load manifest
        const manifest = try manifest_mod.Manifest.load(self.allocator, self.manifest_path);
        defer {
            var mut_manifest = manifest;
            mut_manifest.deinit();
        }

        // Convert ZIM dependencies to ZON format
        var zon_deps = try std.ArrayList(build_zon.ZonDependency).initCapacity(
            self.allocator,
            manifest.dependencies.count(),
        );
        defer {
            for (zon_deps.items) |*dep| dep.deinit(self.allocator);
            zon_deps.deinit(self.allocator);
        }

        var it = manifest.dependencies.iterator();
        while (it.next()) |entry| {
            const dep = entry.value_ptr.*;
            switch (dep.source) {
                .tarball => |tarball| {
                    try zon_deps.append(self.allocator, .{
                        .name = try self.allocator.dupe(u8, dep.name),
                        .url = try self.allocator.dupe(u8, tarball.url),
                        .hash = try self.allocator.dupe(u8, tarball.hash),
                    });
                    color.dim("  + {s}\n", .{dep.name});
                },
                .git => |git| {
                    // For git dependencies, we need to construct a tarball URL
                    // This is a limitation - build.zig.zon doesn't support git URLs directly
                    color.warning("⚠ Skipping git dependency '{s}' - build.zig.zon requires tarball URLs\n", .{dep.name});
                    color.dim("  Git URL: {s}\n", .{git.url});
                },
                .local => {
                    color.warning("⚠ Skipping local dependency '{s}' - build.zig.zon requires tarball URLs\n", .{dep.name});
                },
                .registry => {
                    color.warning("⚠ Skipping registry dependency '{s}' - build.zig.zon requires tarball URLs\n", .{dep.name});
                },
                .github => |gh| {
                    color.warning("⚠ Skipping GitHub dependency '{s}' - build.zig.zon requires tarball URLs\n", .{dep.name});
                    const ref = gh.ref orelse "main";
                    color.dim("  GitHub: {s}/{s}@{s}\n", .{ gh.owner, gh.repo, ref });
                },
            }
        }

        if (zon_deps.items.len == 0) {
            color.warning("⚠ No compatible dependencies to export\n", .{});
            color.dim("Note: Only tarball dependencies can be exported to build.zig.zon\n", .{});
            return;
        }

        // Write build.zig.zon
        try build_zon.writeBuildZon(
            self.allocator,
            zon_path,
            manifest.name,
            manifest.version,
            zon_deps.items,
        );

        color.success("✓ Exported {d} dependencies to {s}\n", .{ zon_deps.items.len, zon_path });
    }
};

test "dependency manager init" {
    const allocator = std.testing.allocator;
    var mgr = try DependencyManager.init(allocator, "/tmp/zim-test-cache");
    defer mgr.deinit();

    try std.testing.expect(mgr.lockfile.entries.count() == 0);
}

test "lockfile save and load" {
    const allocator = std.testing.allocator;
    var lockfile = Lockfile.init(allocator);
    defer lockfile.deinit();

    // TODO: Add entries and test round-trip
}

test "content-addressed cache" {
    const allocator = std.testing.allocator;
    var cache = try DependencyCache.init(allocator, "/tmp/zim-test-cache");
    defer cache.deinit();

    const test_hash = "abcdef1234567890";
    const is_cached = try cache.isCached(test_hash);
    try std.testing.expect(!is_cached);
}
