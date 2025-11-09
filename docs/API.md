# ZIM API Documentation

Complete API reference for ZIM - Zig Infrastructure Manager.

## Table of Contents

- [Dependency Management](#dependency-management)
- [Dependency Resolution](#dependency-resolution)
- [Dependency Graph](#dependency-graph)
- [Build.zig.zon Integration](#buildzigzon-integration)
- [Version Management](#version-management)
- [Download & Verification](#download--verification)
- [Git Operations](#git-operations)
- [Toolchain Management](#toolchain-management)
- [Target Management](#target-management)
- [Configuration](#configuration)

---

## Dependency Management

**Module:** `src/deps/deps.zig`

Core dependency management with Babylon-inspired content-addressed caching.

### Types

#### `DependencySource`

Union type representing different dependency sources.

```zig
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
};
```

**Usage:**
```zig
const git_dep = DependencySource{
    .git = .{
        .url = "https://github.com/user/repo",
        .ref = "main",
    },
};

const tarball_dep = DependencySource{
    .tarball = .{
        .url = "https://example.com/package.tar.gz",
        .hash = "sha256:abc123...",
    },
};
```

#### `Dependency`

Dependency metadata with source and hash information.

```zig
pub const Dependency = struct {
    name: []const u8,
    source: DependencySource,
    hash: ?[]const u8 = null,

    pub fn deinit(self: *Dependency, allocator: std.mem.Allocator) void
};
```

#### `LockfileEntry`

Entry in the lockfile for reproducible builds.

```zig
pub const LockfileEntry = struct {
    name: []const u8,
    version: []const u8,
    hash: []const u8,
    source: []const u8,
    dependencies: std.ArrayListUnmanaged([]const u8),

    pub fn deinit(self: *LockfileEntry, allocator: std.mem.Allocator) void
};
```

#### `Lockfile`

Lockfile for reproducible dependency resolution.

```zig
pub const Lockfile = struct {
    entries: std.StringHashMapUnmanaged(LockfileEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Lockfile
    pub fn deinit(self: *Lockfile) void
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Lockfile
    pub fn save(self: *Lockfile, path: []const u8) !void
};
```

**Example:**
```zig
var lockfile = try Lockfile.load(allocator, "zim.lock");
defer lockfile.deinit();

// Save updated lockfile
try lockfile.save("zim.lock");
```

#### `DependencyCache`

Content-addressed cache for dependencies (Babylon-inspired).

```zig
pub const DependencyCache = struct {
    allocator: std.mem.Allocator,
    cache_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !DependencyCache
    pub fn deinit(self: *DependencyCache) void
    pub fn getCachePath(self: *DependencyCache, hash: []const u8) ![]const u8
    pub fn isCached(self: *DependencyCache, hash: []const u8) !bool
    pub fn store(self: *DependencyCache, hash: []const u8, source_path: []const u8) !void
    pub fn retrieve(self: *DependencyCache, hash: []const u8, dest_path: []const u8) !void
    pub fn clean(self: *DependencyCache, keep_hashes: []const []const u8) !void
};
```

**Cache Structure:**
```
~/.cache/zim/deps/
├── ab/
│   └── cd/
│       └── abcdef1234567890...
└── 12/
    └── 34/
        └── 1234567890abcdef...
```

**Example:**
```zig
var cache = try DependencyCache.init(allocator, "/home/user/.cache/zim");
defer cache.deinit();

// Check if cached
if (try cache.isCached("abcdef123...")) {
    try cache.retrieve("abcdef123...", "/tmp/package");
}
```

#### `DependencyManager`

High-level dependency manager with Babylon-inspired features.

```zig
pub const DependencyManager = struct {
    allocator: std.mem.Allocator,
    cache: DependencyCache,
    lockfile: Lockfile,
    manifest_path: []const u8,
    lockfile_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, cache_dir: []const u8) !DependencyManager
    pub fn deinit(self: *DependencyManager) void
    pub fn initProject(self: *DependencyManager, project_name: []const u8) !void
    pub fn addDependency(self: *DependencyManager, dep: Dependency) !void
    pub fn fetch(self: *DependencyManager) !void
    pub fn graphDisplay(self: *DependencyManager) !void
    pub fn verify(self: *DependencyManager) !void
    pub fn update(self: *DependencyManager, dependency_name: ?[]const u8) !void
    pub fn cleanCache(self: *DependencyManager) !void
};
```

**Example:**
```zig
var mgr = try DependencyManager.init(allocator, "/home/user/.cache/zim");
defer mgr.deinit();

// Initialize new project
try mgr.initProject("my-awesome-project");

// Fetch dependencies
try mgr.fetch();

// Display dependency graph
try mgr.graphDisplay();

// Verify all dependencies
try mgr.verify();
```

---

## Dependency Resolution

**Module:** `src/deps/resolver.zig`

Semantic version-aware dependency resolution with conflict detection.

### Types

#### `Requirement`

Version requirement for a package.

```zig
pub const Requirement = struct {
    package: []const u8,
    constraint: VersionConstraint,
    required_by: []const u8,

    pub fn init(allocator: std.mem.Allocator, package: []const u8, constraint: VersionConstraint, required_by: []const u8) !Requirement
    pub fn deinit(self: *Requirement, allocator: std.mem.Allocator) void
};
```

#### `ResolvedPackage`

Resolved package version.

```zig
pub const ResolvedPackage = struct {
    name: []const u8,
    version: SemanticVersion,

    pub fn deinit(self: *ResolvedPackage, allocator: std.mem.Allocator) void
};
```

#### `Conflict`

Dependency version conflict.

```zig
pub const Conflict = struct {
    package: []const u8,
    requirements: std.ArrayList(Requirement),

    pub fn deinit(self: *Conflict) void
};
```

#### `Resolver`

Dependency resolver with conflict detection.

```zig
pub const Resolver = struct {
    allocator: std.mem.Allocator,
    requirements: std.StringHashMap(std.ArrayList(Requirement)),
    resolved: std.StringHashMap(ResolvedPackage),

    pub fn init(allocator: std.mem.Allocator) Resolver
    pub fn deinit(self: *Resolver) void
    pub fn addRequirement(self: *Resolver, name: []const u8, constraint: VersionConstraint, required_by: []const u8) !void
    pub fn resolve(self: *Resolver) !void
    pub fn detectConflicts(self: *Resolver, allocator: std.mem.Allocator) !?std.ArrayList(Conflict)
};
```

**Example:**
```zig
var resolver = Resolver.init(allocator);
defer resolver.deinit();

// Add requirements
try resolver.addRequirement("zsync", .{ .caret = try SemanticVersion.parse("0.7.0") }, "my-project");
try resolver.addRequirement("zsync", .{ .exact = try SemanticVersion.parse("0.6.0") }, "other-dep");

// Detect conflicts
if (try resolver.detectConflicts(allocator)) |conflicts| {
    defer conflicts.deinit();
    for (conflicts.items) |conflict| {
        std.debug.print("Conflict for {s}\n", .{conflict.package});
    }
}

// Resolve dependencies
try resolver.resolve();
```

---

## Dependency Graph

**Module:** `src/deps/graph.zig`

Dependency graph visualization and cycle detection.

### Types

#### `GraphNode`

Dependency graph node for visualization.

```zig
pub const GraphNode = struct {
    name: []const u8,
    version: []const u8,
    children: std.ArrayList(*GraphNode),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) !*GraphNode
    pub fn deinit(self: *GraphNode) void
    pub fn addChild(self: *GraphNode, child: *GraphNode) !void
};
```

**Example:**
```zig
const root = try GraphNode.init(allocator, "my-project", "1.0.0");
defer root.deinit();

const child = try GraphNode.init(allocator, "zsync", "0.7.1");
try root.addChild(child);
```

#### `DepStats`

Dependency statistics.

```zig
pub const DepStats = struct {
    total_deps: usize,
    unique_deps: usize,
    max_depth: usize,
    total_size: usize, // In bytes (if available)
};
```

### Functions

#### `printTree`

Print dependency tree with beautiful ASCII art.

```zig
pub fn printTree(root: *GraphNode, writer: anytype) !void
```

**Output:**
```
my-project @ 1.0.0
├── zsync @ 0.7.1
│   └── zlog @ 0.1.0
└── zhttp @ 0.1.4
    └── zsync @ 0.7.1
```

**Example:**
```zig
const stdout = std.io.getStdOut().writer();
try printTree(root, stdout);
```

#### `detectCycles`

Detect circular dependencies.

```zig
pub fn detectCycles(
    root: *GraphNode,
    allocator: std.mem.Allocator,
) !?[]const []const u8
```

**Returns:** Cycle path if detected, null otherwise.

**Example:**
```zig
if (try detectCycles(root, allocator)) |cycle| {
    defer allocator.free(cycle);
    std.debug.print("Cycle detected: ", .{});
    for (cycle) |name| {
        std.debug.print("{s} -> ", .{name});
    }
    std.debug.print("\n", .{});
}
```

#### `calculateStats`

Calculate dependency statistics.

```zig
pub fn calculateStats(root: *GraphNode, allocator: std.mem.Allocator) !DepStats
```

**Example:**
```zig
const stats = try calculateStats(root, allocator);
std.debug.print("Total deps: {d}\n", .{stats.total_deps});
std.debug.print("Unique deps: {d}\n", .{stats.unique_deps});
std.debug.print("Max depth: {d}\n", .{stats.max_depth});
```

---

## Build.zig.zon Integration

**Module:** `src/deps/build_zon.zig`

Native Zig package format integration.

### Types

#### `ZonDependency`

Build.zig.zon dependency entry.

```zig
pub const ZonDependency = struct {
    name: []const u8,
    url: []const u8,
    hash: []const u8,

    pub fn deinit(self: *ZonDependency, allocator: std.mem.Allocator) void
};
```

### Functions

#### `parseBuildZon`

Parse build.zig.zon file.

```zig
pub fn parseBuildZon(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(ZonDependency)
```

**Example:**
```zig
var deps = try parseBuildZon(allocator, "build.zig.zon");
defer {
    for (deps.items) |*dep| dep.deinit(allocator);
    deps.deinit();
}

for (deps.items) |dep| {
    std.debug.print("{s}: {s}\n", .{dep.name, dep.url});
}
```

#### `writeBuildZon`

Write build.zig.zon file.

```zig
pub fn writeBuildZon(
    allocator: std.mem.Allocator,
    path: []const u8,
    project_name: []const u8,
    version: []const u8,
    deps: []const ZonDependency,
) !void
```

**Example:**
```zig
const deps = [_]ZonDependency{
    .{ .name = "zsync", .url = "https://github.com/...", .hash = "1220..." },
};

try writeBuildZon(allocator, "build.zig.zon", "my-project", "1.0.0", &deps);
```

**Generated Format:**
```zig
.{
    .name = "my-project",
    .version = "1.0.0",
    .minimum_zig_version = "0.16.0",

    .dependencies = .{
        .zsync = .{
            .url = "https://github.com/...",
            .hash = "1220...",
        },
    },

    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

---

## Version Management

**Module:** `src/util/version.zig`

Semantic versioning with npm-style constraints.

### Types

#### `SemanticVersion`

Semantic version (major.minor.patch).

```zig
pub const SemanticVersion = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn parse(version_str: []const u8) !SemanticVersion
    pub fn compare(self: *const SemanticVersion, other: *const SemanticVersion) i8
    pub fn format(self: *const SemanticVersion, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void
};
```

**Example:**
```zig
const v1 = try SemanticVersion.parse("1.2.3");
const v2 = try SemanticVersion.parse("1.3.0");

if (v1.compare(&v2) < 0) {
    std.debug.print("{} is older than {}\n", .{v1, v2});
}
```

#### `VersionConstraint`

Version constraint (npm-style).

```zig
pub const VersionConstraint = union(enum) {
    exact: SemanticVersion,      // =1.2.3
    gte: SemanticVersion,         // >=1.2.3
    lt: SemanticVersion,          // <2.0.0
    caret: SemanticVersion,       // ^1.2.3 (>=1.2.3 <2.0.0)
    tilde: SemanticVersion,       // ~1.2.3 (>=1.2.3 <1.3.0)
    wildcard: struct {
        major: u32,
        minor: ?u32,
    },                            // 1.* or 1.2.*
    any,                          // *

    pub fn parse(constraint_str: []const u8) !VersionConstraint
    pub fn matches(self: *const VersionConstraint, version: *const SemanticVersion) bool
};
```

**Examples:**
```zig
const exact = try VersionConstraint.parse("1.2.3");
const caret = try VersionConstraint.parse("^1.2.3");  // >=1.2.3 <2.0.0
const tilde = try VersionConstraint.parse("~1.2.3");  // >=1.2.3 <1.3.0
const gte = try VersionConstraint.parse(">=1.0.0");
const wildcard = try VersionConstraint.parse("1.*");

const version = try SemanticVersion.parse("1.5.0");

if (caret.matches(&version)) {
    std.debug.print("Version matches ^1.2.3\n", .{});
}
```

**Constraint Semantics:**
- `^1.2.3`: >=1.2.3 <2.0.0 (compatible changes)
- `~1.2.3`: >=1.2.3 <1.3.0 (patch-level changes)
- `>=1.2.3`: Greater than or equal to 1.2.3
- `<2.0.0`: Less than 2.0.0
- `1.*`: 1.x.x (any minor/patch)
- `1.2.*`: 1.2.x (any patch)
- `*`: Any version

---

## Download & Verification

**Module:** `src/util/download.zig`

HTTP downloads with cryptographic verification using Ghost Stack.

### Functions

#### `downloadFile`

Download file from URL using zhttp.

```zig
pub fn downloadFile(
    allocator: std.mem.Allocator,
    url: []const u8,
    output_path: []const u8,
) !void
```

**Example:**
```zig
try downloadFile(allocator, "https://ziglang.org/download/0.16.0/zig-0.16.0.tar.xz", "/tmp/zig.tar.xz");
```

#### `downloadFileVerified`

Download and verify file hash using zcrypto.

```zig
pub fn downloadFileVerified(
    allocator: std.mem.Allocator,
    url: []const u8,
    output_path: []const u8,
    expected_hash: []const u8,
) !void
```

**Example:**
```zig
const expected = "abcdef1234567890...";
try downloadFileVerified(allocator, url, "/tmp/file", expected);
// Automatically deletes file if hash doesn't match
```

#### `computeFileSha256`

Compute SHA-256 hash of file using streaming.

```zig
pub fn computeFileSha256(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) ![]const u8
```

**Returns:** Hex-encoded SHA-256 hash.

**Example:**
```zig
const hash = try computeFileSha256(allocator, "/tmp/file");
defer allocator.free(hash);
std.debug.print("SHA-256: {s}\n", .{hash});
```

#### `extractTarXz`

Extract .tar.xz archive.

```zig
pub fn extractTarXz(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    output_dir: []const u8,
) !void
```

**Example:**
```zig
try extractTarXz(allocator, "/tmp/package.tar.xz", "/opt/zig");
```

---

## Git Operations

**Module:** `src/util/git.zig`

Git repository operations for dependency fetching.

### Functions

#### `clone`

Clone git repository with shallow depth.

```zig
pub fn clone(
    allocator: std.mem.Allocator,
    url: []const u8,
    dest_path: []const u8,
    ref: ?[]const u8,
) !void
```

**Parameters:**
- `url`: Git repository URL
- `dest_path`: Destination directory
- `ref`: Optional branch/tag/commit (null for default branch)

**Example:**
```zig
// Clone default branch
try clone(allocator, "https://github.com/user/repo", "/tmp/repo", null);

// Clone specific branch
try clone(allocator, "https://github.com/user/repo", "/tmp/repo", "main");

// Clone specific tag
try clone(allocator, "https://github.com/user/repo", "/tmp/repo", "v1.0.0");
```

#### `fetch`

Fetch updates from remote repository.

```zig
pub fn fetch(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
) !void
```

**Example:**
```zig
try fetch(allocator, "/tmp/repo");
```

#### `getCurrentCommit`

Get current commit hash.

```zig
pub fn getCurrentCommit(
    allocator: std.mem.Allocator,
    repo_path: []const u8,
) ![]const u8
```

**Returns:** Full commit hash.

**Example:**
```zig
const commit = try getCurrentCommit(allocator, "/tmp/repo");
defer allocator.free(commit);
std.debug.print("Current commit: {s}\n", .{commit});
```

---

## Toolchain Management

**Module:** `src/toolchain/toolchain.zig`

Zig compiler version management (rustup-style).

### Types

#### `ToolchainManager`

Manages multiple Zig toolchain installations.

```zig
pub const ToolchainManager = struct {
    allocator: std.mem.Allocator,
    toolchains_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, toolchains_dir: []const u8) !ToolchainManager
    pub fn deinit(self: *ToolchainManager) void
    pub fn install(self: *ToolchainManager, version: []const u8) !void
    pub fn list(self: *ToolchainManager) !void
    pub fn use(self: *ToolchainManager, version: []const u8) !void
    pub fn pin(self: *ToolchainManager, version: []const u8) !void
    pub fn uninstall(self: *ToolchainManager, version: []const u8) !void
    pub fn getActive(self: *ToolchainManager) !?[]const u8
};
```

**Example:**
```zig
var mgr = try ToolchainManager.init(allocator, "/home/user/.zim/toolchains");
defer mgr.deinit();

// Install Zig version
try mgr.install("0.16.0");

// List installed toolchains
try mgr.list();

// Set global active version
try mgr.use("0.16.0");

// Pin project to version
try mgr.pin("0.16.0");

// Get active version
if (try mgr.getActive()) |version| {
    defer allocator.free(version);
    std.debug.print("Active: {s}\n", .{version});
}
```

---

## Target Management

**Module:** `src/target/target.zig`

Cross-compilation target management.

### Types

#### `Target`

Cross-compilation target.

```zig
pub const Target = struct {
    triple: []const u8,
    arch: []const u8,
    os: []const u8,
    abi: ?[]const u8,

    pub fn parse(allocator: std.mem.Allocator, triple: []const u8) !Target
    pub fn deinit(self: *Target, allocator: std.mem.Allocator) void
};
```

**Example:**
```zig
var target = try Target.parse(allocator, "x86_64-linux-gnu");
defer target.deinit(allocator);

std.debug.print("Arch: {s}\n", .{target.arch});  // x86_64
std.debug.print("OS: {s}\n", .{target.os});      // linux
```

#### `TargetManager`

Manages cross-compilation targets.

```zig
pub const TargetManager = struct {
    allocator: std.mem.Allocator,
    targets_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, targets_dir: []const u8) !TargetManager
    pub fn deinit(self: *TargetManager) void
    pub fn add(self: *TargetManager, triple: []const u8) !void
    pub fn list(self: *TargetManager) !void
    pub fn remove(self: *TargetManager, triple: []const u8) !void
};
```

**Example:**
```zig
var mgr = try TargetManager.init(allocator, "/home/user/.zim/targets");
defer mgr.deinit();

// Add target
try mgr.add("wasm32-wasi");

// List targets
try mgr.list();

// Remove target
try mgr.remove("wasm32-wasi");
```

**Common Targets:**
- `x86_64-linux-gnu` - Linux x86_64
- `aarch64-linux-gnu` - Linux ARM64
- `x86_64-windows-gnu` - Windows x86_64
- `x86_64-macos` - macOS x86_64
- `aarch64-macos` - macOS ARM64 (Apple Silicon)
- `wasm32-wasi` - WebAssembly WASI
- `wasm32-freestanding` - WebAssembly bare

---

## Configuration

**Module:** `src/config/config.zig`

ZIM configuration management.

### Types

#### `Config`

ZIM configuration.

```zig
pub const Config = struct {
    cache_dir: []const u8,
    toolchains_dir: []const u8,
    targets_dir: []const u8,
    registry_url: ?[]const u8,
    require_signatures: bool,
    allowed_sources: std.ArrayList([]const u8),
    denied_sources: std.ArrayList([]const u8),
    ca_bundle: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) Config
    pub fn deinit(self: *Config) void
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Config
    pub fn save(self: *Config, path: []const u8) !void
    pub fn getDefault(allocator: std.mem.Allocator) !Config
};
```

**Example:**
```zig
var config = try Config.load(allocator, "/home/user/.config/zim/config.toml");
defer config.deinit();

std.debug.print("Cache dir: {s}\n", .{config.cache_dir});
std.debug.print("Require signatures: {}\n", .{config.require_signatures});
```

**Configuration File Format:**
```toml
[cache]
dir = "/custom/cache/dir"
max_size = 10737418240  # 10GB

[registry]
url = "https://zim.example.com/registry"
mirror = "https://mirror.example.com"

[policy]
require_signatures = true
allowed_sources = ["github.com", "gitlab.com"]
denied_sources = []

[network]
ca_bundle = "/etc/ssl/certs/ca-bundle.crt"
```

---

## Error Handling

All ZIM APIs use Zig's error union return types. Common errors:

```zig
error.OutOfMemory          // Memory allocation failed
error.FileNotFound         // File doesn't exist
error.NetworkError         // Network operation failed
error.HashMismatch         // Hash verification failed
error.InvalidVersion       // Version string parsing failed
error.VersionConflict      // Dependency version conflict
error.CircularDependency   // Circular dependency detected
error.InvalidTarget        // Invalid target triple
error.NotCached            // Dependency not in cache
```

**Example Error Handling:**
```zig
const version = SemanticVersion.parse("1.2.3") catch |err| {
    std.debug.print("Failed to parse version: {}\n", .{err});
    return err;
};

mgr.fetch() catch |err| {
    switch (err) {
        error.NetworkError => std.debug.print("Network error\n", .{}),
        error.HashMismatch => std.debug.print("Hash verification failed\n", .{}),
        else => return err,
    }
};
```

---

## Best Practices

### Memory Management

Always use defer for cleanup:

```zig
var mgr = try DependencyManager.init(allocator, cache_dir);
defer mgr.deinit();

const hash = try computeFileSha256(allocator, path);
defer allocator.free(hash);
```

### Error Propagation

Use `try` for error propagation:

```zig
try mgr.fetch();
try mgr.verify();
```

### Resource Cleanup

Use `errdefer` for cleanup on error:

```zig
var list = std.ArrayList(Dependency).init(allocator);
errdefer {
    for (list.items) |*dep| dep.deinit(allocator);
    list.deinit();
}
```

### Version Constraints

Prefer semantic constraints over exact versions:

```zig
// Good - allows compatible updates
const constraint = try VersionConstraint.parse("^1.2.3");

// Avoid - too restrictive
const constraint = try VersionConstraint.parse("1.2.3");
```

---

## See Also

- [CLI Documentation](CLI.md)
- [Configuration Guide](CONFIGURATION.md)
- [README](../README.md)
