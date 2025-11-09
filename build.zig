const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get all Ghost Stack dependencies
    const zsync = b.dependency("zsync", .{
        .target = target,
        .optimize = optimize,
    });
    const flash = b.dependency("flash", .{
        .target = target,
        .optimize = optimize,
    });
    const flare = b.dependency("flare", .{
        .target = target,
        .optimize = optimize,
    });
    const zlog = b.dependency("zlog", .{
        .target = target,
        .optimize = optimize,
    });
    const zontom = b.dependency("zontom", .{
        .target = target,
        .optimize = optimize,
    });
    const phantom = b.dependency("phantom", .{
        .target = target,
        .optimize = optimize,
    });
    const zhttp = b.dependency("zhttp", .{
        .target = target,
        .optimize = optimize,
    });
    const zigzag = b.dependency("zigzag", .{
        .target = target,
        .optimize = optimize,
    });
    const zpack = b.dependency("zpack", .{
        .target = target,
        .optimize = optimize,
    });
    const zcrypto = b.dependency("zcrypto", .{
        .target = target,
        .optimize = optimize,
    });
    const ztime = b.dependency("ztime", .{
        .target = target,
        .optimize = optimize,
    });
    const zcrate = b.dependency("zcrate", .{
        .target = target,
        .optimize = optimize,
    });
    const ghostls = b.dependency("ghostls", .{
        .target = target,
        .optimize = optimize,
    });
    const ghostlang = b.dependency("ghostlang", .{
        .target = target,
        .optimize = optimize,
    });
    const ghostspec = b.dependency("ghostspec", .{
        .target = target,
        .optimize = optimize,
    });
    // Create ZIM library module with all dependencies
    const mod = b.addModule("zim", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "zsync", .module = zsync.module("zsync") },
            .{ .name = "flash", .module = flash.module("flash") },
            .{ .name = "flare", .module = flare.module("flare") },
            .{ .name = "zlog", .module = zlog.module("zlog") },
            .{ .name = "zontom", .module = zontom.module("zontom") },
            .{ .name = "phantom", .module = phantom.module("phantom") },
            .{ .name = "zhttp", .module = zhttp.module("zhttp") },
            .{ .name = "zigzag", .module = zigzag.module("zigzag") },
            .{ .name = "zpack", .module = zpack.module("zpack") },
            .{ .name = "zcrypto", .module = zcrypto.module("zcrypto") },
            .{ .name = "ztime", .module = ztime.module("ztime") },
            .{ .name = "zcrate", .module = zcrate.module("zcrate") },
            .{ .name = "ghostls", .module = ghostls.module("ghostls") },
            .{ .name = "ghostlang", .module = ghostlang.module("ghostlang") },
            .{ .name = "ghostspec", .module = ghostspec.module("ghostspec") },
        },
    });

    // Create ZIM executable
    const exe = b.addExecutable(.{
        .name = "zim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zim", .module = mod },
                .{ .name = "zsync", .module = zsync.module("zsync") },
                .{ .name = "flash", .module = flash.module("flash") },
                .{ .name = "flare", .module = flare.module("flare") },
                .{ .name = "zlog", .module = zlog.module("zlog") },
                .{ .name = "zontom", .module = zontom.module("zontom") },
                .{ .name = "phantom", .module = phantom.module("phantom") },
                .{ .name = "zhttp", .module = zhttp.module("zhttp") },
                .{ .name = "zigzag", .module = zigzag.module("zigzag") },
                .{ .name = "zpack", .module = zpack.module("zpack") },
                .{ .name = "zcrypto", .module = zcrypto.module("zcrypto") },
                .{ .name = "ztime", .module = ztime.module("ztime") },
                .{ .name = "zcrate", .module = zcrate.module("zcrate") },
                .{ .name = "ghostls", .module = ghostls.module("ghostls") },
                .{ .name = "ghostlang", .module = ghostlang.module("ghostlang") },
                .{ .name = "ghostspec", .module = ghostspec.module("ghostspec") },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Add unit tests
    const unit_test_step = b.step("test-unit", "Run unit tests");

    // Create test exports module that provides access to source code
    const test_exports = b.addModule("test_exports", .{
        .root_source_file = b.path("src/test_exports.zig"),
        .target = target,
    });

    // Create test imports module
    const test_imports = b.addModule("test_imports", .{
        .root_source_file = b.path("test/test_imports.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "test_exports", .module = test_exports },
        },
    });

    // System Zig unit tests
    const system_zig_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/unit/test_system_zig.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "test_imports", .module = test_imports },
            },
        }),
    });
    const run_system_zig_tests = b.addRunArtifact(system_zig_tests);
    unit_test_step.dependOn(&run_system_zig_tests.step);
    test_step.dependOn(&run_system_zig_tests.step);

    // ZLS unit tests
    const zls_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/unit/test_zls.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "test_imports", .module = test_imports },
            },
        }),
    });
    const run_zls_tests = b.addRunArtifact(zls_tests);
    unit_test_step.dependOn(&run_zls_tests.step);
    test_step.dependOn(&run_zls_tests.step);

    // Benchmarks
    const bench_step = b.step("bench", "Run benchmarks");

    // System Zig benchmarks
    const system_zig_bench = b.addExecutable(.{
        .name = "bench_system_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/benchmarks/bench_system_zig.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "test_imports", .module = test_imports },
            },
        }),
    });
    b.installArtifact(system_zig_bench);
    const run_system_zig_bench = b.addRunArtifact(system_zig_bench);
    bench_step.dependOn(&run_system_zig_bench.step);

    // ZLS benchmarks
    const zls_bench = b.addExecutable(.{
        .name = "bench_zls",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/benchmarks/bench_zls.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "test_imports", .module = test_imports },
            },
        }),
    });
    b.installArtifact(zls_bench);
    const run_zls_bench = b.addRunArtifact(zls_bench);
    bench_step.dependOn(&run_zls_bench.step);

    // Memory leak check step (uses testing allocator)
    const memcheck_step = b.step("memcheck", "Run memory leak detection tests");
    memcheck_step.dependOn(unit_test_step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
