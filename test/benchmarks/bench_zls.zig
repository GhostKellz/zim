const std = @import("std");
const test_imports = @import("test_imports");
const zls = test_imports.zls;

const ITERATIONS = 100;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 ZLS Manager Benchmarks\n", .{});
    std.debug.print("=========================\n\n", .{});

    // Benchmark: ZlsManager.init + deinit
    {
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
            mgr.deinit();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("ZlsManager.init+deinit: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: ZlsManager.findSystemZls
    {
        var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
        defer mgr.deinit();

        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            _ = mgr.findSystemZls();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("ZlsManager.findSystemZls: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: ZlsManager.isInstalled
    {
        var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
        defer mgr.deinit();

        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            _ = try mgr.isInstalled();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("ZlsManager.isInstalled: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    // Benchmark: ZlsManager.getVersion (slower operation, fewer iterations)
    {
        var mgr = zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config") catch {
            std.debug.print("ZlsManager.getVersion: Skipped (init failed)\n", .{});
            return;
        };
        defer mgr.deinit();

        if (mgr.findSystemZls() != null) {
            const version_iters = 5;
            var timer = try std.time.Timer.start();
            var i: usize = 0;
            while (i < version_iters) : (i += 1) {
                const version = mgr.getVersion() catch continue;
                defer allocator.free(version);
            }
            const elapsed = timer.read();
            const avg_ns = elapsed / version_iters;
            std.debug.print("ZlsManager.getVersion: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, version_iters });
        }
    }

    // Benchmark: Config generation
    {
        // Create temporary directory
        const tmp_dir = "/tmp/zim_bench_config";
        std.fs.cwd().makeDir(tmp_dir) catch {};
        defer std.fs.cwd().deleteTree(tmp_dir) catch {};

        var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", tmp_dir);
        defer mgr.deinit();

        const config_iters = 10;
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < config_iters) : (i += 1) {
            try mgr.generateConfig();
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / config_iters;
        std.debug.print("ZlsManager.generateConfig: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, config_iters });
    }

    // Memory usage benchmark
    {
        std.debug.print("\n📊 Memory Usage\n", .{});
        std.debug.print("----------------\n", .{});

        var mgr = try zls.ZlsManager.init(allocator, "/tmp/test_zls", "/tmp/test_config");
        defer mgr.deinit();

        std.debug.print("ZlsManager struct:   {d} bytes\n", .{@sizeOf(zls.ZlsManager)});
        std.debug.print("  - zls_dir:         {d} bytes\n", .{mgr.zls_dir.len});
        std.debug.print("  - config_dir:      {d} bytes\n", .{mgr.config_dir.len});

        if (mgr.findSystemZls() != null) {
            const version = mgr.getVersion() catch null;
            if (version) |v| {
                defer allocator.free(v);
                std.debug.print("Version string:      {d} bytes\n", .{v.len});
            }
        }
    }

    std.debug.print("\n✅ Benchmarks complete\n\n", .{});
}
