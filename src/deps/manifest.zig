const std = @import("std");
const zontom = @import("zontom");
const deps_mod = @import("deps.zig");
const color = @import("../util/color.zig");

const Dependency = deps_mod.Dependency;
const DependencySource = deps_mod.DependencySource;

/// Project manifest (zim.toml)
pub const Manifest = struct {
    allocator: std.mem.Allocator,

    // Project metadata
    name: []const u8,
    version: []const u8,
    zig_version: []const u8,

    // Dependencies
    dependencies: std.StringArrayHashMapUnmanaged(Dependency),
    dev_dependencies: std.StringArrayHashMapUnmanaged(Dependency),

    // Build configuration
    targets: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) Manifest {
        return .{
            .allocator = allocator,
            .name = "",
            .version = "",
            .zig_version = "",
            .dependencies = .{},
            .dev_dependencies = .{},
            .targets = .{},
        };
    }

    pub fn deinit(self: *Manifest) void {
        self.allocator.free(self.name);
        self.allocator.free(self.version);
        self.allocator.free(self.zig_version);

        var dep_it = self.dependencies.iterator();
        while (dep_it.next()) |entry| {
            var dep = entry.value_ptr.*;
            dep.deinit(self.allocator);
        }
        self.dependencies.deinit(self.allocator);

        var dev_dep_it = self.dev_dependencies.iterator();
        while (dev_dep_it.next()) |entry| {
            var dep = entry.value_ptr.*;
            dep.deinit(self.allocator);
        }
        self.dev_dependencies.deinit(self.allocator);

        for (self.targets.items) |target| {
            self.allocator.free(target);
        }
        self.targets.deinit(self.allocator);
    }

    /// Load manifest from zim.toml file
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Manifest {
        color.dim("📄 Loading manifest: {s}\n", .{path});

        const file = try std.fs.cwd().openFile(path, .{});
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

        // Parse TOML using zontom
        var table = try zontom.parse(allocator, content);
        defer table.deinit();

        var manifest = Manifest.init(allocator);
        errdefer manifest.deinit();

        // Extract project metadata
        if (table.get("project")) |project_value| {
            switch (project_value) {
                .table => |project| {
                    if (project.get("name")) |name_val| {
                        switch (name_val) {
                            .string => |name| manifest.name = try allocator.dupe(u8, name),
                            else => {},
                        }
                    }

                    if (project.get("version")) |version_val| {
                        switch (version_val) {
                            .string => |version| manifest.version = try allocator.dupe(u8, version),
                            else => {},
                        }
                    }

                    if (project.get("zig")) |zig_val| {
                        switch (zig_val) {
                            .string => |zig_version| manifest.zig_version = try allocator.dupe(u8, zig_version),
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        // Extract dependencies
        if (table.get("dependencies")) |deps_value| {
            switch (deps_value) {
                .table => |deps_table| try parseDependencies(allocator, deps_table, &manifest.dependencies),
                else => {},
            }
        }

        // Extract dev dependencies
        if (table.get("dev-dependencies")) |dev_deps_value| {
            switch (dev_deps_value) {
                .table => |dev_deps_table| try parseDependencies(allocator, dev_deps_table, &manifest.dev_dependencies),
                else => {},
            }
        }

        // Extract targets
        if (table.get("targets")) |targets_value| {
            switch (targets_value) {
                .table => |targets_table| {
                    if (targets_table.get("default")) |default_val| {
                        switch (default_val) {
                            .array => |target_array| {
                                for (target_array.items.items) |item| {
                                    switch (item) {
                                        .string => |target| {
                                            const target_copy = try allocator.dupe(u8, target);
                                            try manifest.targets.append(allocator, target_copy);
                                        },
                                        else => {},
                                    }
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }

        color.success("✓ Loaded manifest: {s}\n", .{manifest.name});
        return manifest;
    }

    fn parseDependencies(
        allocator: std.mem.Allocator,
        deps_table: *const zontom.Table,
        output: *std.StringArrayHashMapUnmanaged(Dependency),
    ) !void {
        var it = deps_table.map.iterator();
        while (it.next()) |entry| {
            const dep_name = entry.key_ptr.*;
            const dep_value = entry.value_ptr.*;

            const dep = try parseDependency(allocator, dep_name, dep_value);
            try output.put(allocator, try allocator.dupe(u8, dep_name), dep);
        }
    }

    fn parseDependency(
        allocator: std.mem.Allocator,
        name: []const u8,
        value: zontom.Value,
    ) !Dependency {
        // Dependency can be specified as a table with git/tarball/local/registry
        switch (value) {
            .table => |dep_table| {
                // Check for git source
                if (dep_table.get("git")) |git_val| {
                    switch (git_val) {
                        .string => |git_url| {
                            const ref = if (dep_table.get("ref")) |ref_val| blk: {
                                switch (ref_val) {
                                    .string => |r| break :blk r,
                                    else => break :blk "main",
                                }
                            } else "main";

                            return Dependency{
                                .name = try allocator.dupe(u8, name),
                                .source = .{
                                    .git = .{
                                        .url = try allocator.dupe(u8, git_url),
                                        .ref = try allocator.dupe(u8, ref),
                                    },
                                },
                            };
                        },
                        else => {},
                    }
                }

                // Check for tarball source
                if (dep_table.get("tarball")) |tarball_val| {
                    switch (tarball_val) {
                        .string => |tarball_url| {
                            const hash = if (dep_table.get("hash")) |hash_val| blk: {
                                switch (hash_val) {
                                    .string => |h| break :blk h,
                                    else => break :blk "",
                                }
                            } else "";

                            return Dependency{
                                .name = try allocator.dupe(u8, name),
                                .source = .{
                                    .tarball = .{
                                        .url = try allocator.dupe(u8, tarball_url),
                                        .hash = try allocator.dupe(u8, hash),
                                    },
                                },
                            };
                        },
                        else => {},
                    }
                }

                // Check for local path source
                if (dep_table.get("path")) |path_val| {
                    switch (path_val) {
                        .string => |local_path| {
                            return Dependency{
                                .name = try allocator.dupe(u8, name),
                                .source = .{
                                    .local = .{
                                        .path = try allocator.dupe(u8, local_path),
                                    },
                                },
                            };
                        },
                        else => {},
                    }
                }

                // Check for registry source (future)
                if (dep_table.get("version")) |version_val| {
                    switch (version_val) {
                        .string => |version| {
                            return Dependency{
                                .name = try allocator.dupe(u8, name),
                                .source = .{
                                    .registry = .{
                                        .name = try allocator.dupe(u8, name),
                                        .version = try allocator.dupe(u8, version),
                                    },
                                },
                            };
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        // If we get here, it's an unsupported format
        color.warning("⚠ Unsupported dependency format for: {s}\n", .{name});
        return error.InvalidDependencyFormat;
    }

    /// Save manifest to file
    pub fn save(self: *Manifest, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Write header
        try file.writeAll("# ZIM project manifest\n\n");

        // Write project section
        try file.writeAll("[project]\n");
        const project_section = try std.fmt.allocPrint(
            self.allocator,
            "name = \"{s}\"\nversion = \"{s}\"\nzig = \"{s}\"\n\n",
            .{ self.name, self.version, self.zig_version },
        );
        defer self.allocator.free(project_section);
        try file.writeAll(project_section);

        // Write dependencies
        if (self.dependencies.count() > 0) {
            try file.writeAll("[dependencies]\n");
            var it = self.dependencies.iterator();
            while (it.next()) |entry| {
                const line = try formatDependency(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                defer self.allocator.free(line);
                try file.writeAll(line);
            }
            try file.writeAll("\n");
        }

        // Write dev dependencies
        if (self.dev_dependencies.count() > 0) {
            try file.writeAll("[dev-dependencies]\n");
            var it = self.dev_dependencies.iterator();
            while (it.next()) |entry| {
                const line = try formatDependency(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                defer self.allocator.free(line);
                try file.writeAll(line);
            }
            try file.writeAll("\n");
        }

        // Write targets
        if (self.targets.items.len > 0) {
            try file.writeAll("[targets]\n");
            try file.writeAll("default = [");
            for (self.targets.items, 0..) |target, i| {
                if (i > 0) try file.writeAll(", ");
                const quoted = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{target});
                defer self.allocator.free(quoted);
                try file.writeAll(quoted);
            }
            try file.writeAll("]\n");
        }

        color.success("✓ Saved manifest to: {s}\n", .{path});
    }

    fn formatDependency(allocator: std.mem.Allocator, name: []const u8, dep: Dependency) ![]const u8 {
        return switch (dep.source) {
            .git => |git| std.fmt.allocPrint(
                allocator,
                "{s} = {{ git = \"{s}\", ref = \"{s}\" }}\n",
                .{ name, git.url, git.ref },
            ),
            .tarball => |tar| std.fmt.allocPrint(
                allocator,
                "{s} = {{ tarball = \"{s}\", hash = \"{s}\" }}\n",
                .{ name, tar.url, tar.hash },
            ),
            .local => |local| std.fmt.allocPrint(
                allocator,
                "{s} = {{ path = \"{s}\" }}\n",
                .{ name, local.path },
            ),
            .registry => |reg| std.fmt.allocPrint(
                allocator,
                "{s} = {{ version = \"{s}\" }}\n",
                .{ name, reg.version },
            ),
            .github => |gh| blk: {
                const ref_str = if (gh.ref) |r|
                    try std.fmt.allocPrint(allocator, "@{s}", .{r})
                else
                    try allocator.dupe(u8, "");
                defer allocator.free(ref_str);

                break :blk std.fmt.allocPrint(
                    allocator,
                    "{s} = \"gh/{s}/{s}{s}\"\n",
                    .{ name, gh.owner, gh.repo, ref_str },
                );
            },
        };
    }
};

test "manifest parsing" {
    const allocator = std.testing.allocator;
    _ = allocator;
}
