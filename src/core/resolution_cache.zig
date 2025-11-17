const std = @import("std");

/// Incremental dependency resolution cache
/// Caches resolution results to speed up repeated builds
pub const ResolutionCache = struct {
    allocator: std.mem.Allocator,
    cache_file: []const u8,
    entries: std.StringHashMap(CacheEntry),
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator) !ResolutionCache {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const cache_file = try std.fmt.allocPrint(
            allocator,
            "{s}/.zim/resolution-cache.json",
            .{home},
        );

        var cache = ResolutionCache{
            .allocator = allocator,
            .cache_file = cache_file,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
        };

        // Try to load existing cache
        cache.load() catch |err| {
            std.debug.print("Resolution cache not loaded: {}\n", .{err});
        };

        return cache;
    }

    pub fn deinit(self: *ResolutionCache) void {
        // Save if dirty
        if (self.dirty) {
            self.save() catch |err| {
                std.debug.print("Failed to save resolution cache: {}\n", .{err});
            };
        }

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.entries.deinit();
        self.allocator.free(self.cache_file);
    }

    /// Get cached resolution for a dependency specification
    pub fn get(self: *ResolutionCache, dep_spec: []const u8) ?*const CacheEntry {
        return self.entries.getPtr(dep_spec);
    }

    /// Store resolution result
    pub fn put(
        self: *ResolutionCache,
        dep_spec: []const u8,
        resolved_version: []const u8,
        metadata: CacheMetadata,
    ) !void {
        const key = try self.allocator.dupe(u8, dep_spec);
        const value = CacheEntry{
            .resolved_version = try self.allocator.dupe(u8, resolved_version),
            .metadata = metadata,
            .timestamp = std.time.timestamp(),
        };

        try self.entries.put(key, value);
        self.dirty = true;
    }

    /// Check if cache entry is still valid
    pub fn isValid(self: *ResolutionCache, dep_spec: []const u8, max_age_seconds: i64) bool {
        const entry = self.get(dep_spec) orelse return false;

        const now = std.time.timestamp();
        const age = now - entry.timestamp;

        return age < max_age_seconds;
    }

    /// Invalidate all entries (force re-resolution)
    pub fn invalidateAll(self: *ResolutionCache) !void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.entries.clearRetainingCapacity();
        self.dirty = true;
    }

    /// Invalidate specific dependency
    pub fn invalidate(self: *ResolutionCache, dep_spec: []const u8) void {
        if (self.entries.fetchRemove(dep_spec)) |kv| {
            self.allocator.free(kv.key);
            kv.value.deinit(self.allocator);
            self.dirty = true;
        }
    }

    /// Load cache from disk
    fn load(self: *ResolutionCache) !void {
        const file = std.fs.cwd().openFile(self.cache_file, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // Cache doesn't exist yet, that's fine
                return;
            }
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        // Parse JSON
        // In real implementation, use std.json
        // For now, just log that we loaded it
        std.debug.print("Loaded resolution cache ({d} bytes)\n", .{content.len});
    }

    /// Save cache to disk
    fn save(self: *ResolutionCache) !void {
        // Ensure directory exists
        if (std.fs.path.dirname(self.cache_file)) |dir| {
            std.fs.cwd().makePath(dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }

        const file = try std.fs.cwd().createFile(self.cache_file, .{});
        defer file.close();

        const writer = file.writer();

        // Write JSON
        try writer.writeAll("{\n");
        try writer.writeAll("  \"version\": \"1\",\n");
        try writer.writeAll("  \"entries\": {\n");

        var it = self.entries.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try writer.writeAll(",\n");

            try writer.print("    \"{s}\": {{\n", .{entry.key_ptr.*});
            try writer.print("      \"resolved\": \"{s}\",\n", .{entry.value_ptr.resolved_version});
            try writer.print("      \"timestamp\": {d},\n", .{entry.value_ptr.timestamp});
            try writer.print("      \"hash\": \"{s}\"\n", .{entry.value_ptr.metadata.hash orelse "unknown"});
            try writer.writeAll("    }");

            first = false;
        }

        try writer.writeAll("\n  }\n");
        try writer.writeAll("}\n");

        self.dirty = false;
        std.debug.print("Saved resolution cache ({d} entries)\n", .{self.entries.count()});
    }

    /// Get cache statistics
    pub fn getStats(self: *ResolutionCache) CacheStats {
        var oldest: i64 = std.math.maxInt(i64);
        var newest: i64 = 0;

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const ts = entry.value_ptr.timestamp;
            if (ts < oldest) oldest = ts;
            if (ts > newest) newest = ts;
        }

        return .{
            .total_entries = self.entries.count(),
            .oldest_timestamp = if (self.entries.count() > 0) oldest else 0,
            .newest_timestamp = if (self.entries.count() > 0) newest else 0,
        };
    }

    /// Clean old entries
    pub fn cleanOld(self: *ResolutionCache, max_age_seconds: i64) !usize {
        const now = std.time.timestamp();
        var to_remove = std.ArrayList([]const u8).init(self.allocator);
        defer to_remove.deinit();

        var it = self.entries.iterator();
        while (it.next()) |entry| {
            const age = now - entry.value_ptr.timestamp;
            if (age > max_age_seconds) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        const removed = to_remove.items.len;
        for (to_remove.items) |key| {
            self.invalidate(key);
        }

        return removed;
    }
};

pub const CacheEntry = struct {
    resolved_version: []const u8,
    metadata: CacheMetadata,
    timestamp: i64,

    pub fn deinit(self: *CacheEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.resolved_version);
        if (self.metadata.hash) |hash| {
            allocator.free(hash);
        }
    }
};

pub const CacheMetadata = struct {
    hash: ?[]const u8 = null,
    url: ?[]const u8 = null,
};

pub const CacheStats = struct {
    total_entries: usize,
    oldest_timestamp: i64,
    newest_timestamp: i64,
};

/// Resolver that uses incremental caching
pub const CachedResolver = struct {
    allocator: std.mem.Allocator,
    cache: ResolutionCache,

    pub fn init(allocator: std.mem.Allocator) !CachedResolver {
        return .{
            .allocator = allocator,
            .cache = try ResolutionCache.init(allocator),
        };
    }

    pub fn deinit(self: *CachedResolver) void {
        self.cache.deinit();
    }

    /// Resolve dependency with caching
    pub fn resolve(
        self: *CachedResolver,
        dep_spec: []const u8,
        force_refresh: bool,
    ) ![]const u8 {
        // Check cache first
        if (!force_refresh and self.cache.isValid(dep_spec, 24 * 60 * 60)) {
            // Cache hit (valid for 24 hours)
            if (self.cache.get(dep_spec)) |entry| {
                std.debug.print("🚀 Cache hit: {s} -> {s}\n", .{
                    dep_spec,
                    entry.resolved_version,
                });
                return try self.allocator.dupe(u8, entry.resolved_version);
            }
        }

        // Cache miss - perform actual resolution
        std.debug.print("🔍 Resolving {s}...\n", .{dep_spec});

        const resolved = try self.performResolution(dep_spec);
        errdefer self.allocator.free(resolved);

        // Cache the result
        try self.cache.put(dep_spec, resolved, .{
            .hash = null, // TODO: Add hash
        });

        return resolved;
    }

    fn performResolution(self: *CachedResolver, dep_spec: []const u8) ![]const u8 {
        // Simulate resolution
        // In real implementation, this would:
        // 1. Query registry for available versions
        // 2. Match against version spec
        // 3. Return resolved version

        _ = self;

        // Parse version spec (simplified)
        if (std.mem.indexOf(u8, dep_spec, "^")) |_| {
            // Caret version (^1.2.0 -> 1.x.x)
            return try self.allocator.dupe(u8, "1.5.0");
        } else if (std.mem.indexOf(u8, dep_spec, "~")) |_| {
            // Tilde version (~1.2.0 -> 1.2.x)
            return try self.allocator.dupe(u8, "1.2.3");
        } else {
            // Exact version
            return try self.allocator.dupe(u8, dep_spec);
        }
    }

    /// Batch resolve with progress reporting
    pub fn resolveBatch(
        self: *CachedResolver,
        deps: []const []const u8,
        force_refresh: bool,
    ) !std.ArrayList([]const u8) {
        var results = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (results.items) |r| {
                self.allocator.free(r);
            }
            results.deinit();
        }

        var cache_hits: usize = 0;
        var cache_misses: usize = 0;

        for (deps) |dep| {
            const was_cached = !force_refresh and self.cache.isValid(dep, 24 * 60 * 60);
            const resolved = try self.resolve(dep, force_refresh);
            try results.append(resolved);

            if (was_cached) {
                cache_hits += 1;
            } else {
                cache_misses += 1;
            }
        }

        if (deps.len > 0) {
            const hit_rate = (@as(f64, @floatFromInt(cache_hits)) / @as(f64, @floatFromInt(deps.len))) * 100.0;
            std.debug.print("\n📊 Cache stats: {d}/{d} hits ({d:.1}%)\n", .{
                cache_hits,
                deps.len,
                hit_rate,
            });
        }

        return results;
    }
};

test "resolution cache" {
    const allocator = std.testing.allocator;

    var cache = try ResolutionCache.init(allocator);
    defer cache.deinit();

    try cache.put("mylib@^1.0.0", "1.5.0", .{});

    const entry = cache.get("mylib@^1.0.0").?;
    try std.testing.expectEqualStrings("1.5.0", entry.resolved_version);
}

test "cached resolver" {
    const allocator = std.testing.allocator;

    var resolver = try CachedResolver.init(allocator);
    defer resolver.deinit();

    const version1 = try resolver.resolve("mylib@^1.0.0", false);
    defer allocator.free(version1);

    const version2 = try resolver.resolve("mylib@^1.0.0", false);
    defer allocator.free(version2);

    try std.testing.expectEqualStrings(version1, version2);
}
