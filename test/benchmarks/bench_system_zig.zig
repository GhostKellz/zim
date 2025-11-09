const std = @import("std");
const test_imports = @import("test_imports");
const system_zig = test_imports.system_zig;

const ITERATIONS = 1000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 System Zig Benchmarks\n", .{});
    std.debug.print("========================\n\n", .{});

    // Benchmark: SystemZig.init
    {
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            const sys_zig = system_zig.SystemZig.init(allocator);
            _ = sys_zig;
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("SystemZig.init:     {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: SystemZig.isInstalled
    {
        var sys_zig = system_zig.SystemZig.init(allocator);
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            _ = sys_zig.isInstalled();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("SystemZig.isInstalled: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: SystemZig.getPath
    {
        var sys_zig = system_zig.SystemZig.init(allocator);
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            _ = sys_zig.getPath();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("SystemZig.getPath:  {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: SystemZig.getVersion (slower, fewer iterations)
    {
        var check_sys_zig = system_zig.SystemZig.init(allocator);
        if (check_sys_zig.getPath() != null) {
        const version_iters = 10;
        var sys_zig = system_zig.SystemZig.init(allocator);
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < version_iters) : (i += 1) {
            const version = try sys_zig.getVersion();
            if (version) |v| {
                defer allocator.free(v);
            }
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / version_iters;
        std.debug.print("SystemZig.getVersion: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, version_iters });
        }
    }

    // Memory usage benchmark
    {
        std.debug.print("\n📊 Memory Usage\n", .{});
        std.debug.print("----------------\n", .{});

        var sys_zig = system_zig.SystemZig.init(allocator);
        std.debug.print("SystemZig struct:   {d} bytes\n", .{@sizeOf(system_zig.SystemZig)});

        const version = try sys_zig.getVersion();
        if (version) |v| {
            defer allocator.free(v);
            std.debug.print("Version string:     {d} bytes\n", .{v.len});
        }

        const info = try sys_zig.getInfo();
        if (info) |*i| {
            var mut_info = i.*;
            defer mut_info.deinit();
            std.debug.print("ZigInfo struct:     {d} bytes\n", .{@sizeOf(system_zig.ZigInfo)});
            std.debug.print("  - path:           {d} bytes\n", .{i.path.len});
            std.debug.print("  - version:        {d} bytes\n", .{i.version.len});
        }
    }

    std.debug.print("\n✅ Benchmarks complete\n\n", .{});
}
