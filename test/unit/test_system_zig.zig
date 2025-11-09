const std = @import("std");
const testing = std.testing;
const test_imports = @import("test_imports");
const system_zig = test_imports.system_zig;

test "SystemZig.init creates valid instance" {
    const allocator = testing.allocator;
    const sys_zig = system_zig.SystemZig.init(allocator);

    // Should not crash
    try testing.expect(@TypeOf(sys_zig) == system_zig.SystemZig);
}

test "SystemZig.getPath detects system Zig or returns null" {
    const allocator = testing.allocator;
    var sys_zig = system_zig.SystemZig.init(allocator);

    const path = sys_zig.getPath();

    // Either we have system Zig or we don't - both are valid
    if (path) |p| {
        // If found, should be an absolute path
        try testing.expect(std.fs.path.isAbsolute(p));
    }
}

test "SystemZig.isInstalled returns boolean without error" {
    const allocator = testing.allocator;
    var sys_zig = system_zig.SystemZig.init(allocator);

    // Should return true or false, not error
    const installed = sys_zig.isInstalled();
    try testing.expect(installed == true or installed == false);
}

test "SystemZig.getVersion handles missing system Zig gracefully" {
    const allocator = testing.allocator;
    var sys_zig = system_zig.SystemZig.init(allocator);

    const version = try sys_zig.getVersion();

    if (version) |v| {
        // If we got a version, it should be valid and we must free it
        defer allocator.free(v);
        try testing.expect(v.len > 0);
    }
}

test "SystemZig.getInfo memory management" {
    const allocator = testing.allocator;
    var sys_zig = system_zig.SystemZig.init(allocator);

    const info = try sys_zig.getInfo();

    if (info) |*i| {
        // Ensure proper cleanup
        var mut_info = i.*;
        defer mut_info.deinit();

        try testing.expect(i.path.len > 0);
        try testing.expect(i.version.len > 0);
    }
}

test "detectActiveZig with null ZIM path" {
    const allocator = testing.allocator;

    const result = try system_zig.detectActiveZig(allocator, null);

    if (result) |*info| {
        var mut_info = info.*;
        defer mut_info.deinit();

        // Should detect system Zig if available
        if (mut_info.is_system) {
            try testing.expect(mut_info.path.len > 0);
        }
    }
}

test "ZigInfo.print does not crash" {
    const allocator = testing.allocator;

    const info = system_zig.ZigInfo{
        .path = try allocator.dupe(u8, "/usr/bin/zig"),
        .version = try allocator.dupe(u8, "0.16.0"),
        .is_system = true,
        .allocator = allocator,
    };

    defer {
        var mut_info = info;
        mut_info.deinit();
    }

    // Should not crash when printing
    info.print();
}

// Memory leak test - ensures no leaks in typical usage
test "SystemZig no memory leaks in typical workflow" {
    const allocator = testing.allocator;
    var sys_zig = system_zig.SystemZig.init(allocator);

    // Run several operations
    _ = sys_zig.isInstalled();
    _ = sys_zig.getPath();

    const version = try sys_zig.getVersion();
    if (version) |v| {
        defer allocator.free(v);
        try testing.expect(v.len > 0);
    }

    const info = try sys_zig.getInfo();
    if (info) |*i| {
        var mut_info = i.*;
        defer mut_info.deinit();
        try testing.expect(mut_info.path.len > 0);
    }

    // testing.allocator will detect any leaks
}
