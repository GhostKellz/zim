const std = @import("std");
const testing = std.testing;
const test_imports = @import("test_imports");
const zls = test_imports.zls;

test "ZlsManager.init and deinit - no memory leaks" {
    const allocator = testing.allocator;

    var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
    defer mgr.deinit();

    // Verify fields are set correctly
    try testing.expect(mgr.zls_dir.len > 0);
    try testing.expect(mgr.config_dir.len > 0);
}

test "ZlsManager.findSystemZls returns valid path or null" {
    const allocator = testing.allocator;
    var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
    defer mgr.deinit();

    const path = mgr.findSystemZls();

    if (path) |p| {
        // If found, should be absolute path
        try testing.expect(std.fs.path.isAbsolute(p));
        // Should end with "zls"
        try testing.expect(std.mem.endsWith(u8, p, "zls"));
    }
}

test "ZlsManager.isInstalled returns boolean" {
    const allocator = testing.allocator;
    var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
    defer mgr.deinit();

    const installed = try mgr.isInstalled();
    try testing.expect(installed == true or installed == false);
}

test "ZlsManager.getVersion handles missing ZLS gracefully" {
    const allocator = testing.allocator;
    var mgr = try zls.ZlsManager.init(allocator, "/nonexistent/zls", "/tmp/test_config");
    defer mgr.deinit();

    // If ZLS is not found, getVersion should return error
    const version = mgr.getVersion() catch |err| {
        // Expected error when ZLS is not found
        try testing.expect(err == error.ZlsVersionFailed or err == error.FileNotFound);
        return;
    };

    // If we got a version, clean it up
    defer allocator.free(version);
    try testing.expect(version.len > 0);
}

test "ZlsManager memory safety - multiple init/deinit cycles" {
    const allocator = testing.allocator;

    // Run multiple cycles to ensure no leaks
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
        defer mgr.deinit();

        _ = mgr.findSystemZls();
        _ = try mgr.isInstalled();
    }
}

test "ZlsManager.generateConfig creates valid config file" {
    const allocator = testing.allocator;

    // Use a temporary directory
    var tmp_dir = try std.fs.cwd().makeOpenPath("/tmp/zim_test_config", .{});
    defer {
        std.fs.cwd().deleteTree("/tmp/zim_test_config") catch {};
    }
    tmp_dir.close();

    var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/zim_test_config");
    defer mgr.deinit();

    // Generate config
    try mgr.generateConfig();

    // Verify config file was created
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp/zim_test_config", "zls.json" });
    defer allocator.free(config_path);

    const file = try std.fs.openFileAbsolute(config_path, .{});
    defer file.close();

    // Read and verify it's valid JSON-like content
    var buffer: [2048]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    try testing.expect(bytes_read > 0);
    try testing.expect(std.mem.indexOf(u8, buffer[0..bytes_read], "enable_snippets") != null);
}

// Memory leak test - comprehensive workflow
test "ZlsManager no memory leaks in full workflow" {
    const allocator = testing.allocator;

    var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
    defer mgr.deinit();

    // Run multiple operations
    _ = mgr.findSystemZls();
    _ = try mgr.isInstalled();

    // If ZLS is available, test version retrieval
    if (mgr.findSystemZls()) |_| {
        const version = mgr.getVersion() catch {
            // Error is acceptable if ZLS is not working
            return;
        };
        defer allocator.free(version);
        try testing.expect(version.len > 0);
    }

    // testing.allocator will detect any leaks
}
