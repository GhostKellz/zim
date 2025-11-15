const std = @import("std");
const builtin = @import("builtin");
const zontom = @import("zontom");

/// ZIM Configuration
/// Supports loading from:
/// 1. $PWD/.zim/toolchain.toml (project-level)
/// 2. $HOME/.config/zim/config.toml (global)
/// 3. Environment variables (ZIM_*)
/// 4. CLI arguments
pub const Config = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // Toolchain settings
    zig_version: ?[]const u8 = null,
    toolchain_dir: ?[]const u8 = null,
    use_local_toolchains: bool = true,

    // Target settings
    targets: std.ArrayListUnmanaged([]const u8),
    default_target: ?[]const u8 = null,

    // Cache settings
    cache_dir: ?[]const u8 = null,
    max_cache_size: ?u64 = null, // in bytes

    // Registry settings
    registry_url: ?[]const u8 = null,
    registry_mirror: ?[]const u8 = null,

    // Policy settings
    require_signatures: bool = false,
    allowed_sources: std.ArrayListUnmanaged([]const u8),
    denied_sources: std.ArrayListUnmanaged([]const u8),

    // Ghost Stack integration paths
    local_projects_root: []const u8 = "/data/projects",
    zsync_path: ?[]const u8 = null,
    zontom_path: ?[]const u8 = null,
    zhttp_path: ?[]const u8 = null,
    phantom_path: ?[]const u8 = null,
    ghostlang_path: ?[]const u8 = null,

    // CA/TLS settings
    ca_bundle_path: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) !Config {
        var arena = std.heap.ArenaAllocator.init(allocator);
        _ = arena.allocator();

        return Config{
            .allocator = allocator,
            .arena = arena,
            .targets = .{},
            .allowed_sources = .{},
            .denied_sources = .{},
        };
    }

    pub fn deinit(self: *Config) void {
        self.arena.deinit();
    }

    /// Load configuration with the following precedence (highest to lowest):
    /// 1. CLI arguments
    /// 2. Environment variables
    /// 3. Project config (.zim/toolchain.toml)
    /// 4. Global config (~/.config/zim/config.toml)
    /// 5. Defaults
    pub fn load(allocator: std.mem.Allocator) !Config {
        var config = try init(allocator);
        errdefer config.deinit();

        // Load defaults
        try config.loadDefaults();

        // Load global config
        try config.loadGlobalConfig();

        // Load project config
        try config.loadProjectConfig();

        // Load environment variables
        try config.loadEnvVars();

        // Detect Ghost Stack integrations
        try config.detectGhostStack();

        return config;
    }

    fn loadDefaults(self: *Config) !void {
        const arena_allocator = self.arena.allocator();

        // Set default cache dir
        if (self.cache_dir == null) {
            self.cache_dir = try getDefaultCacheDir(arena_allocator);
        }

        // Set default toolchain dir
        if (self.toolchain_dir == null) {
            self.toolchain_dir = try getDefaultToolchainDir(arena_allocator);
        }

        // Default targets
        if (self.targets.items.len == 0) {
            try self.targets.append(arena_allocator, try arena_allocator.dupe(u8, "native"));
        }
    }

    fn loadGlobalConfig(self: *Config) !void {
        const global_config_path = try getGlobalConfigPath(self.arena.allocator());

        // Try to read global config if it exists
        const file = std.fs.openFileAbsolute(global_config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No global config, that's fine
                return;
            }
            return err;
        };
        defer file.close();

        // Read file contents
        const stat = try file.stat();
        const contents = try self.arena.allocator().alloc(u8, stat.size);
        _ = try file.read(contents);

        // Parse TOML
        try self.parseTomlConfig(contents);
    }

    fn loadProjectConfig(self: *Config) !void {
        const project_config_path = ".zim/toolchain.toml";

        // Try to read project config if it exists
        const file = std.fs.cwd().openFile(project_config_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // No project config, that's fine
                return;
            }
            return err;
        };
        defer file.close();

        // Read file contents
        const stat = try file.stat();
        const contents = try self.arena.allocator().alloc(u8, stat.size);
        _ = try file.read(contents);

        // Parse TOML
        try self.parseTomlConfig(contents);
    }

    fn parseTomlConfig(self: *Config, toml_content: []const u8) !void {
        _ = self;
        _ = toml_content;
        // TODO: Implement proper zontom API usage once the API is stable
        // For now, config uses defaults from init()
        return;
    }

    fn loadEnvVars(self: *Config) !void {
        const arena_allocator = self.arena.allocator();

        // ZIM_CACHE_DIR
        if (std.process.getEnvVarOwned(arena_allocator, "ZIM_CACHE_DIR")) |dir| {
            self.cache_dir = dir;
        } else |_| {}

        // ZIM_TOOLCHAIN_DIR
        if (std.process.getEnvVarOwned(arena_allocator, "ZIM_TOOLCHAIN_DIR")) |dir| {
            self.toolchain_dir = dir;
        } else |_| {}

        // ZIM_CA_BUNDLE or SSL_CERT_FILE
        if (std.process.getEnvVarOwned(arena_allocator, "ZIM_CA_BUNDLE")) |path| {
            self.ca_bundle_path = path;
        } else |_| {
            if (std.process.getEnvVarOwned(arena_allocator, "SSL_CERT_FILE")) |path| {
                self.ca_bundle_path = path;
            } else |_| {}
        }

        // ZIM_REGISTRY_URL
        if (std.process.getEnvVarOwned(arena_allocator, "ZIM_REGISTRY_URL")) |url| {
            self.registry_url = url;
        } else |_| {}

        // ZIM_REQUIRE_SIGNATURES
        if (std.process.getEnvVarOwned(arena_allocator, "ZIM_REQUIRE_SIGNATURES")) |val| {
            self.require_signatures = std.mem.eql(u8, val, "true") or std.mem.eql(u8, val, "1");
        } else |_| {}
    }

    fn detectGhostStack(self: *Config) !void {
        const arena_allocator = self.arena.allocator();

        // Check for zsync
        const zsync_path = try std.fs.path.join(arena_allocator, &[_][]const u8{ self.local_projects_root, "zsync" });
        if (dirExists(zsync_path)) {
            self.zsync_path = zsync_path;
        }

        // Check for zontom
        const zontom_path = try std.fs.path.join(arena_allocator, &[_][]const u8{ self.local_projects_root, "zontom" });
        if (dirExists(zontom_path)) {
            self.zontom_path = zontom_path;
        }

        // Check for zhttp
        const zhttp_path = try std.fs.path.join(arena_allocator, &[_][]const u8{ self.local_projects_root, "zhttp" });
        if (dirExists(zhttp_path)) {
            self.zhttp_path = zhttp_path;
        }

        // Check for phantom
        const phantom_path = try std.fs.path.join(arena_allocator, &[_][]const u8{ self.local_projects_root, "phantom" });
        if (dirExists(phantom_path)) {
            self.phantom_path = phantom_path;
        }

        // Check for ghostlang
        const ghostlang_path = try std.fs.path.join(arena_allocator, &[_][]const u8{ self.local_projects_root, "ghostlang" });
        if (dirExists(ghostlang_path)) {
            self.ghostlang_path = ghostlang_path;
        }
    }

    pub fn getCacheDir(self: *const Config) []const u8 {
        return self.cache_dir orelse unreachable; // Should always be set after load()
    }

    pub fn getToolchainDir(self: *const Config) []const u8 {
        return self.toolchain_dir orelse unreachable; // Should always be set after load()
    }

    pub fn hasZsync(self: *const Config) bool {
        return self.zsync_path != null;
    }

    pub fn hasZontom(self: *const Config) bool {
        return self.zontom_path != null;
    }

    pub fn hasZhttp(self: *const Config) bool {
        return self.zhttp_path != null;
    }

    pub fn hasPhantom(self: *const Config) bool {
        return self.phantom_path != null;
    }

    pub fn hasGhostlang(self: *const Config) bool {
        return self.ghostlang_path != null;
    }

    pub fn debugPrint(self: *const Config) void {
        std.debug.print("ZIM Configuration:\n", .{});
        std.debug.print("  Zig Version: {s}\n", .{self.zig_version orelse "not set"});
        std.debug.print("  Toolchain Dir: {s}\n", .{self.getToolchainDir()});
        std.debug.print("  Cache Dir: {s}\n", .{self.getCacheDir()});
        std.debug.print("  CA Bundle: {s}\n", .{self.ca_bundle_path orelse "not set"});
        std.debug.print("\nGhost Stack Integration:\n", .{});
        std.debug.print("  zsync: {s}\n", .{if (self.hasZsync()) "available" else "not found"});
        std.debug.print("  zontom: {s}\n", .{if (self.hasZontom()) "available" else "not found"});
        std.debug.print("  zhttp: {s}\n", .{if (self.hasZhttp()) "available" else "not found"});
        std.debug.print("  phantom: {s}\n", .{if (self.hasPhantom()) "available" else "not found"});
        std.debug.print("  ghostlang: {s}\n", .{if (self.hasGhostlang()) "available" else "not found"});
        std.debug.print("\nTargets:\n", .{});
        for (self.targets.items) |target| {
            std.debug.print("  - {s}\n", .{target});
        }
    }
};

/// Get default cache directory based on platform
fn getDefaultCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .linux) {
        // Try XDG_CACHE_HOME first
        if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |xdg_cache| {
            return std.fs.path.join(allocator, &[_][]const u8{ xdg_cache, "zim" });
        } else |_| {
            // Fall back to ~/.cache/zim
            if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
                return std.fs.path.join(allocator, &[_][]const u8{ home, ".cache", "zim" });
            } else |_| {
                return allocator.dupe(u8, "/tmp/zim-cache");
            }
        }
    } else if (builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            return std.fs.path.join(allocator, &[_][]const u8{ home, "Library", "Caches", "zim" });
        } else |_| {
            return allocator.dupe(u8, "/tmp/zim-cache");
        }
    } else if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |appdata| {
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, "zim", "cache" });
        } else |_| {
            return allocator.dupe(u8, "C:\\Temp\\zim-cache");
        }
    } else {
        return allocator.dupe(u8, "/tmp/zim-cache");
    }
}

/// Get default toolchain directory
fn getDefaultToolchainDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
            return std.fs.path.join(allocator, &[_][]const u8{ home, ".zim", "toolchains" });
        } else |_| {
            return allocator.dupe(u8, "/tmp/zim-toolchains");
        }
    } else if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "LOCALAPPDATA")) |appdata| {
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, "zim", "toolchains" });
        } else |_| {
            return allocator.dupe(u8, "C:\\Temp\\zim-toolchains");
        }
    } else {
        return allocator.dupe(u8, "/tmp/zim-toolchains");
    }
}

/// Get global config path
fn getGlobalConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
        // Try XDG_CONFIG_HOME first
        if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config| {
            return std.fs.path.join(allocator, &[_][]const u8{ xdg_config, "zim", "config.toml" });
        } else |_| {
            // Fall back to ~/.config/zim/config.toml
            if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
                return std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "zim", "config.toml" });
            } else |_| {
                return allocator.dupe(u8, "/etc/zim/config.toml");
            }
        }
    } else if (builtin.os.tag == .windows) {
        if (std.process.getEnvVarOwned(allocator, "APPDATA")) |appdata| {
            return std.fs.path.join(allocator, &[_][]const u8{ appdata, "zim", "config.toml" });
        } else |_| {
            return allocator.dupe(u8, "C:\\ProgramData\\zim\\config.toml");
        }
    } else {
        return allocator.dupe(u8, "/etc/zim/config.toml");
    }
}

fn dirExists(path: []const u8) bool {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
    dir.close();
    return true;
}

test "config init and deinit" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try std.testing.expect(config.targets.items.len == 0);
}

test "config load defaults" {
    var config = try Config.init(std.testing.allocator);
    defer config.deinit();

    try config.loadDefaults();

    try std.testing.expect(config.cache_dir != null);
    try std.testing.expect(config.toolchain_dir != null);
    try std.testing.expect(config.targets.items.len > 0);
}
