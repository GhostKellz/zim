const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("../config/config.zig");
const toolchain_mod = @import("../toolchain/toolchain.zig");
const deps_mod = @import("../deps/deps.zig");
const target_mod = @import("../target/target.zig");
const zls_mod = @import("../zls/zls.zig");
const doctor_mod = @import("doctor.zig");
const self_update_mod = @import("../util/self_update.zig");
const color = @import("../util/color.zig");

/// Command represents all available ZIM commands
pub const Command = enum {
    // Toolchain commands
    toolchain,
    install, // shorthand for toolchain install
    use, // shorthand for toolchain use

    // ZLS commands
    zls,

    // Target commands
    target,

    // Dependency commands
    deps,

    // Cache commands
    cache,

    // Policy commands
    policy,
    verify,

    // Utility commands
    doctor,
    update,
    version,
    help,

    // Future commands
    mcp,
    ci,
};

pub const SubCommand = enum {
    // Toolchain subcommands
    install,
    use_cmd, // 'use' is a keyword
    pin,
    list,
    current,

    // ZLS subcommands
    doctor,
    config,
    update,
    info,

    // Target subcommands
    add_target,
    remove_target,

    // Deps subcommands
    init,
    add_dep,
    fetch,
    graph,
    import_zon,
    export_zon,

    // Cache subcommands
    status,
    prune,
    clean,
    integrity,

    // Policy subcommands
    audit,

    // Doctor subcommands
    workspace,

    // CI subcommands
    bootstrap,
};

pub const CommandError = error{
    UnknownCommand,
    UnknownSubCommand,
    InvalidArguments,
    MissingArguments,
    MissingSubCommand,
};

pub const CliOptions = struct {
    json: bool = false,
    verbose: bool = false,
    quiet: bool = false,
    cache_dir: ?[]const u8 = null,
    config_file: ?[]const u8 = null,

    pub fn deinit(self: *CliOptions, allocator: std.mem.Allocator) void {
        if (self.cache_dir) |dir| allocator.free(dir);
        if (self.config_file) |file| allocator.free(file);
    }
};

pub const ParsedCommand = struct {
    command: Command,
    subcommand: ?SubCommand = null,
    args: []const []const u8,
    options: CliOptions,

    pub fn deinit(self: *ParsedCommand, allocator: std.mem.Allocator) void {
        self.options.deinit(allocator);
    }
};

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    if (args.len < 2) {
        printHelp();
        return 1;
    }

    var parsed = try parseArgs(allocator, args);
    defer parsed.deinit(allocator);

    return executeCommand(allocator, &parsed);
}

fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedCommand {
    var options = CliOptions{};
    var command: ?Command = null;
    var subcommand: ?SubCommand = null;
    var positional_args = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return CommandError.InvalidArguments;
    defer positional_args.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Check for global flags
        if (std.mem.eql(u8, arg, "--json")) {
            options.json = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
            options.quiet = true;
        } else if (std.mem.eql(u8, arg, "--cache-dir")) {
            i += 1;
            if (i >= args.len) return CommandError.MissingArguments;
            options.cache_dir = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) return CommandError.MissingArguments;
            options.config_file = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return ParsedCommand{
                .command = .help,
                .args = &[_][]const u8{},
                .options = options,
            };
        } else if (std.mem.eql(u8, arg, "--version")) {
            return ParsedCommand{
                .command = .version,
                .args = &[_][]const u8{},
                .options = options,
            };
        } else if (command == null) {
            // First positional arg is the command
            command = try parseCommand(arg);
        } else if (subcommand == null and needsSubCommand(command.?)) {
            // Second positional arg might be a subcommand
            subcommand = parseSubCommand(command.?, arg) catch {
                // Not a subcommand, treat as positional arg
                try positional_args.append(allocator, arg);
                continue;
            };
        } else {
            // All other args are positional
            try positional_args.append(allocator, arg);
        }
    }

    if (command == null) {
        return CommandError.UnknownCommand;
    }

    // Validate subcommand requirement
    // Doctor is special - it can work with or without a subcommand
    if (needsSubCommand(command.?) and subcommand == null and command.? != .doctor) {
        return CommandError.MissingSubCommand;
    }

    return ParsedCommand{
        .command = command.?,
        .subcommand = subcommand,
        .args = try positional_args.toOwnedSlice(allocator),
        .options = options,
    };
}

fn parseCommand(cmd: []const u8) !Command {
    const commands = std.StaticStringMap(Command).initComptime(.{
        .{ "toolchain", .toolchain },
        .{ "install", .install },
        .{ "use", .use },
        .{ "zls", .zls },
        .{ "target", .target },
        .{ "deps", .deps },
        .{ "cache", .cache },
        .{ "policy", .policy },
        .{ "verify", .verify },
        .{ "doctor", .doctor },
        .{ "update", .update },
        .{ "version", .version },
        .{ "help", .help },
        .{ "mcp", .mcp },
        .{ "ci", .ci },
    });

    return commands.get(cmd) orelse CommandError.UnknownCommand;
}

fn parseSubCommand(parent_cmd: Command, cmd: []const u8) !SubCommand {
    // Handle context-dependent subcommands
    if (std.mem.eql(u8, cmd, "add")) {
        return switch (parent_cmd) {
            .target => .add_target,
            .deps => .add_dep,
            else => CommandError.UnknownSubCommand,
        };
    }
    if (std.mem.eql(u8, cmd, "remove")) {
        return switch (parent_cmd) {
            .target => .remove_target,
            else => CommandError.UnknownSubCommand,
        };
    }

    // Handle all other subcommands
    const subcommands = std.StaticStringMap(SubCommand).initComptime(.{
        .{ "install", .install },
        .{ "use", .use_cmd },
        .{ "pin", .pin },
        .{ "list", .list },
        .{ "current", .current },
        .{ "init", .init },
        .{ "fetch", .fetch },
        .{ "graph", .graph },
        .{ "import", .import_zon },
        .{ "export", .export_zon },
        .{ "status", .status },
        .{ "prune", .prune },
        .{ "clean", .clean },
        .{ "integrity", .integrity },
        .{ "doctor", .doctor },
        .{ "config", .config },
        .{ "update", .update },
        .{ "info", .info },
        .{ "audit", .audit },
        .{ "workspace", .workspace },
        .{ "bootstrap", .bootstrap },
    });

    return subcommands.get(cmd) orelse CommandError.UnknownSubCommand;
}

fn needsSubCommand(cmd: Command) bool {
    return switch (cmd) {
        .toolchain, .zls, .target, .deps, .cache, .policy, .ci, .doctor => true,
        else => false,
    };
}

fn executeCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    return switch (parsed.command) {
        .help => {
            printHelp();
            return 0;
        },
        .version => {
            printVersion();
            return 0;
        },
        .toolchain => executeToolchainCommand(allocator, parsed),
        .install => executeShorthandInstall(allocator, parsed),
        .use => executeShorthandUse(allocator, parsed),
        .zls => executeZlsCommand(allocator, parsed),
        .target => executeTargetCommand(allocator, parsed),
        .deps => executeDepsCommand(allocator, parsed),
        .cache => executeCacheCommand(allocator, parsed),
        .policy => executePolicyCommand(allocator, parsed),
        .verify => executeVerifyCommand(allocator, parsed),
        .doctor => executeDoctorCommand(allocator, parsed),
        .update => executeUpdateCommand(allocator, parsed),
        .mcp => executeMcpCommand(allocator, parsed),
        .ci => executeCiCommand(allocator, parsed),
    };
}

fn executeToolchainCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    // Load config to get toolchain directory
    var config = config_mod.Config.load(allocator) catch |err| {
        std.debug.print("Error loading config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    var mgr = try toolchain_mod.ToolchainManager.init(allocator, config.getToolchainDir());
    defer mgr.deinit();

    return switch (subcmd) {
        .install => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing version argument\n", .{});
                std.debug.print("Usage: zim toolchain install <version>\n", .{});
                return 1;
            }
            mgr.install(parsed.args[0]) catch |err| {
                std.debug.print("Error: Failed to install: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .use_cmd => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing version argument\n", .{});
                std.debug.print("Usage: zim toolchain use <version>\n", .{});
                return 1;
            }
            mgr.use(parsed.args[0]) catch |err| {
                std.debug.print("Error: Failed to switch version: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .pin => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing version argument\n", .{});
                std.debug.print("Usage: zim toolchain pin <version>\n", .{});
                return 1;
            }
            mgr.pin(parsed.args[0]) catch |err| {
                std.debug.print("Error: Failed to pin version: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .list => {
            mgr.list() catch |err| {
                std.debug.print("Error: Failed to list toolchains: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .current => {
            mgr.current() catch |err| {
                std.debug.print("Error: Failed to get current version: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'toolchain'\n", .{});
            return 1;
        },
    };
}

fn executeShorthandInstall(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    var modified = parsed.*;
    modified.command = .toolchain;
    modified.subcommand = .install;
    return executeToolchainCommand(allocator, &modified);
}

fn executeShorthandUse(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    var modified = parsed.*;
    modified.command = .toolchain;
    modified.subcommand = .use_cmd;
    return executeToolchainCommand(allocator, &modified);
}

fn executeTargetCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    // Get targets directory from config
    const targets_dir = target_mod.getDefaultTargetsDir(allocator) catch |err| {
        std.debug.print("Error getting targets directory: {}\n", .{err});
        return 1;
    };
    defer allocator.free(targets_dir);

    // Initialize target manager
    var target_mgr = target_mod.TargetManager.init(allocator, targets_dir) catch |err| {
        std.debug.print("Error initializing target manager: {}\n", .{err});
        return 1;
    };
    defer target_mgr.deinit();

    return switch (subcmd) {
        .add_target => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing target triple\n", .{});
                std.debug.print("Usage: zim target add <triple>\n", .{});
                std.debug.print("Examples: x86_64-linux-gnu, aarch64-linux-gnu, wasm32-wasi\n", .{});
                return 1;
            }

            target_mgr.add(parsed.args[0]) catch |err| {
                std.debug.print("Error adding target: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .list => {
            target_mgr.list() catch |err| {
                std.debug.print("Error listing targets: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .remove_target => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing target triple\n", .{});
                std.debug.print("Usage: zim target remove <triple>\n", .{});
                return 1;
            }

            target_mgr.remove(parsed.args[0]) catch |err| {
                std.debug.print("Error removing target: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'target'\n", .{});
            std.debug.print("Available subcommands: add, list, remove\n", .{});
            return 1;
        },
    };
}

fn executeDepsCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    // Load config to get cache directory
    var config = config_mod.Config.load(allocator) catch |err| {
        std.debug.print("Error loading config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    // Initialize dependency manager
    var dep_mgr = deps_mod.DependencyManager.init(allocator, config.getCacheDir()) catch |err| {
        std.debug.print("Error initializing dependency manager: {}\n", .{err});
        return 1;
    };
    defer dep_mgr.deinit();

    return switch (subcmd) {
        .init => {
            const project_name = if (parsed.args.len > 0)
                parsed.args[0]
            else
                "my-project";

            dep_mgr.initProject(project_name) catch |err| {
                std.debug.print("Error initializing project: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .add_dep => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing dependency name\n", .{});
                std.debug.print("Usage: zim deps add <name> --git <url> [--ref <ref>]\n", .{});
                std.debug.print("       zim deps add <name> --tarball <url> --hash <hash>\n", .{});
                std.debug.print("       zim deps add <name> --path <path>\n", .{});
                return 1;
            }

            const dep_name = parsed.args[0];

            // Parse dependency source from remaining args
            var git_url: ?[]const u8 = null;
            var git_ref: []const u8 = "main";
            var tarball_url: ?[]const u8 = null;
            var tarball_hash: ?[]const u8 = null;
            var local_path: ?[]const u8 = null;

            var i: usize = 1;
            while (i < parsed.args.len) : (i += 1) {
                const arg = parsed.args[i];
                if (std.mem.eql(u8, arg, "--git")) {
                    i += 1;
                    if (i >= parsed.args.len) {
                        std.debug.print("Error: --git requires a URL\n", .{});
                        return 1;
                    }
                    git_url = parsed.args[i];
                } else if (std.mem.eql(u8, arg, "--ref")) {
                    i += 1;
                    if (i >= parsed.args.len) {
                        std.debug.print("Error: --ref requires a reference\n", .{});
                        return 1;
                    }
                    git_ref = parsed.args[i];
                } else if (std.mem.eql(u8, arg, "--tarball")) {
                    i += 1;
                    if (i >= parsed.args.len) {
                        std.debug.print("Error: --tarball requires a URL\n", .{});
                        return 1;
                    }
                    tarball_url = parsed.args[i];
                } else if (std.mem.eql(u8, arg, "--hash")) {
                    i += 1;
                    if (i >= parsed.args.len) {
                        std.debug.print("Error: --hash requires a hash\n", .{});
                        return 1;
                    }
                    tarball_hash = parsed.args[i];
                } else if (std.mem.eql(u8, arg, "--path")) {
                    i += 1;
                    if (i >= parsed.args.len) {
                        std.debug.print("Error: --path requires a path\n", .{});
                        return 1;
                    }
                    local_path = parsed.args[i];
                }
            }

            // Create dependency based on source type
            const dep = if (git_url) |url| deps_mod.Dependency{
                .name = try allocator.dupe(u8, dep_name),
                .source = .{
                    .git = .{
                        .url = try allocator.dupe(u8, url),
                        .ref = try allocator.dupe(u8, git_ref),
                    },
                },
            } else if (tarball_url) |url| blk: {
                if (tarball_hash == null) {
                    std.debug.print("Error: --tarball requires --hash\n", .{});
                    return 1;
                }
                break :blk deps_mod.Dependency{
                    .name = try allocator.dupe(u8, dep_name),
                    .source = .{
                        .tarball = .{
                            .url = try allocator.dupe(u8, url),
                            .hash = try allocator.dupe(u8, tarball_hash.?),
                        },
                    },
                };
            } else if (local_path) |path| deps_mod.Dependency{
                .name = try allocator.dupe(u8, dep_name),
                .source = .{
                    .local = .{
                        .path = try allocator.dupe(u8, path),
                    },
                },
            } else {
                std.debug.print("Error: Must specify --git, --tarball, or --path\n", .{});
                return 1;
            };

            defer {
                var mut_dep = dep;
                mut_dep.deinit(allocator);
            }

            dep_mgr.addDependency(dep) catch |err| {
                std.debug.print("Error adding dependency: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .fetch => {
            dep_mgr.fetch() catch |err| {
                std.debug.print("Error fetching dependencies: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .graph => {
            dep_mgr.graph() catch |err| {
                std.debug.print("Error displaying dependency graph: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .import_zon => {
            // Default to build.zig.zon in current directory
            const zon_path = if (parsed.args.len > 0) parsed.args[0] else "build.zig.zon";

            dep_mgr.importFromZon(zon_path) catch |err| {
                std.debug.print("Error importing from build.zig.zon: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .export_zon => {
            // Default to build.zig.zon in current directory
            const zon_path = if (parsed.args.len > 0) parsed.args[0] else "build.zig.zon";

            dep_mgr.exportToZon(zon_path) catch |err| {
                std.debug.print("Error exporting to build.zig.zon: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'deps'\n", .{});
            std.debug.print("Available subcommands: init, add, fetch, graph, import, export\n", .{});
            return 1;
        },
    };
}

fn executeCacheCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    // Load config to get cache directory
    var config = config_mod.Config.load(allocator) catch |err| {
        std.debug.print("Error loading config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    // Initialize dependency manager for cache operations
    var dep_mgr = deps_mod.DependencyManager.init(allocator, config.getCacheDir()) catch |err| {
        std.debug.print("Error initializing dependency manager: {}\n", .{err});
        return 1;
    };
    defer dep_mgr.deinit();

    return switch (subcmd) {
        .status => {
            std.debug.print("Cache status:\n", .{});
            std.debug.print("  Location: {s}\n", .{config.getCacheDir()});
            // TODO: Show cache statistics (size, entries, etc.)
            std.debug.print("(Detailed statistics not yet implemented)\n", .{});
            return 0;
        },
        .prune => {
            const dry_run = for (parsed.args) |arg| {
                if (std.mem.eql(u8, arg, "--dry-run")) break true;
            } else false;

            if (dry_run) {
                std.debug.print("Dry run: Would prune unused cache entries\n", .{});
                return 0;
            }

            dep_mgr.cleanCache() catch |err| {
                std.debug.print("Error pruning cache: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .clean => {
            dep_mgr.cleanCache() catch |err| {
                std.debug.print("Error cleaning cache: {}\n", .{err});
                return 1;
            };
            color.success("✓ Cache cleaned successfully\n", .{});
            return 0;
        },
        .integrity => {
            doctor_mod.checkCacheIntegrity(allocator) catch |err| {
                color.error_("Error checking cache integrity: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        .doctor => {
            doctor_mod.checkCacheIntegrity(allocator) catch |err| {
                color.error_("Error checking cache integrity: {}\n", .{err});
                return 1;
            };
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'cache'\n", .{});
            std.debug.print("Available subcommands: status, prune, clean, integrity, doctor\n", .{});
            return 1;
        },
    };
}

fn executePolicyCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    _ = allocator;
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    return switch (subcmd) {
        .audit => {
            std.debug.print("Auditing dependencies against policy...\n", .{});
            // TODO: Check dependencies against policy
            std.debug.print("(Not yet implemented)\n", .{});
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'policy'\n", .{});
            return 1;
        },
    };
}

fn executeVerifyCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    _ = parsed;
    std.debug.print("Verifying project integrity...\n\n", .{});

    // Load config
    var config = config_mod.Config.load(allocator) catch |err| {
        std.debug.print("Error loading config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    // Initialize dependency manager
    var dep_mgr = deps_mod.DependencyManager.init(allocator, config.getCacheDir()) catch |err| {
        std.debug.print("Error initializing dependency manager: {}\n", .{err});
        return 1;
    };
    defer dep_mgr.deinit();

    // Verify dependencies
    dep_mgr.verify() catch |err| {
        std.debug.print("Error during verification: {}\n", .{err});
        return 1;
    };

    std.debug.print("\n✓ All integrity checks passed\n", .{});
    return 0;
}

fn executeDoctorCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    const subcmd = parsed.subcommand;

    if (subcmd) |cmd| {
        return switch (cmd) {
            .workspace => {
                doctor_mod.checkWorkspace(allocator) catch |err| {
                    color.error_("Error checking workspace: {}\n", .{err});
                    return 1;
                };
                return 0;
            },
            else => {
                std.debug.print("Unknown doctor subcommand\n", .{});
                return 1;
            },
        };
    }

    // No subcommand - run all diagnostics
    doctor_mod.runDiagnostics(allocator) catch |err| {
        color.error_("Error running diagnostics: {}\n", .{err});
        return 1;
    };

    return 0;
}

fn executeUpdateCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    _ = parsed;

    const version = "0.3.4"; // TODO: Get from build info

    self_update_mod.interactiveUpdate(allocator, version) catch |err| {
        color.error_("Update failed: {}\n", .{err});
        return 1;
    };

    return 0;
}

fn executeMcpCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    _ = allocator;
    _ = parsed;
    std.debug.print("MCP server (Model Context Protocol)\n", .{});
    std.debug.print("(Not yet implemented)\n", .{});
    return 0;
}

fn executeCiCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    _ = allocator;
    const subcmd = parsed.subcommand orelse return CommandError.MissingSubCommand;

    return switch (subcmd) {
        .bootstrap => {
            std.debug.print("Generating CI bootstrap configuration...\n", .{});
            // TODO: Generate reproducible CI environment
            std.debug.print("(Not yet implemented)\n", .{});
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'ci'\n", .{});
            return 1;
        },
    };
}

fn executeZlsCommand(allocator: std.mem.Allocator, parsed: *const ParsedCommand) !u8 {
    var config = config_mod.Config.load(allocator) catch |err| {
        std.debug.print("Error loading config: {}\n", .{err});
        return 1;
    };
    defer config.deinit();

    const zls_dir = try std.fs.path.join(allocator, &[_][]const u8{ config.getToolchainDir(), "zls" });
    defer allocator.free(zls_dir);

    // Use ~/.config/zim for ZLS config
    const home_dir = std.posix.getenv("HOME") orelse "/root";
    const config_dir = try std.fs.path.join(allocator, &[_][]const u8{ home_dir, ".config", "zim" });
    defer allocator.free(config_dir);

    var mgr = try zls_mod.ZlsManager.init(allocator, zls_dir, config_dir);
    defer mgr.deinit();

    const subcmd = parsed.subcommand orelse {
        std.debug.print("Usage: zim zls <command>\n\n", .{});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  doctor     - Run comprehensive ZLS health check\n", .{});
        std.debug.print("  install    - Install ZLS\n", .{});
        std.debug.print("  config     - Generate optimal ZLS configuration\n", .{});
        std.debug.print("  update     - Update ZLS\n", .{});
        std.debug.print("  info       - Show ZLS information\n", .{});
        return 0;
    };

    switch (subcmd) {
        .doctor => {
            try mgr.doctor();
            return 0;
        },
        .install => {
            const version = if (parsed.args.len > 0) parsed.args[0] else null;
            try mgr.install(version);
            return 0;
        },
        .config => {
            try mgr.generateConfig();
            return 0;
        },
        .update => {
            try mgr.update();
            return 0;
        },
        .info => {
            try mgr.info();
            return 0;
        },
        else => {
            std.debug.print("Error: Unknown ZLS subcommand\n", .{});
            return 1;
        },
    }
}

fn printVersion() void {
    color.init();
    color.bold("zim", .{});
    std.debug.print(" ", .{});
    color.cyan("0.1.0-dev", .{});
    std.debug.print("\n", .{});
    std.debug.print("Zig Infrastructure Manager\n", .{});
    std.debug.print("Zig version: ", .{});
    color.green("{s}", .{builtin.zig_version_string});
    std.debug.print("\n", .{});
}

fn printHelp() void {
    color.init();

    color.bold("\nzim", .{});
    std.debug.print(" - Zig Infrastructure Manager\n\n", .{});

    color.bold("USAGE:\n", .{});
    std.debug.print("    zim ", .{});
    color.cyan("<COMMAND>", .{});
    std.debug.print(" [OPTIONS]\n\n", .{});

    color.yellow("TOOLCHAIN COMMANDS:\n", .{});
    printCommand("toolchain install", "<ver>", "Install a Zig toolchain version");
    printCommand("toolchain use", "<ver>", "Set global Zig version (or 'system')");
    printCommand("toolchain pin", "<ver>", "Pin project to specific Zig version");
    printCommand("toolchain list", "", "List installed toolchains");
    printCommand("toolchain current", "", "Show current active Zig version");
    printCommand("install", "<ver>", "Shorthand for 'toolchain install'");
    printCommand("use", "<ver>", "Shorthand for 'toolchain use'");
    std.debug.print("\n", .{});

    color.yellow("ZLS COMMANDS:\n", .{});
    printCommand("zls doctor", "", "Run comprehensive ZLS health check");
    printCommand("zls install", "[ver]", "Install Zig Language Server");
    printCommand("zls config", "", "Generate optimal ZLS configuration");
    printCommand("zls update", "", "Update ZLS to latest version");
    printCommand("zls info", "", "Show ZLS installation information");
    std.debug.print("\n", .{});

    color.yellow("TARGET COMMANDS:\n", .{});
    printCommand("target add", "<triple>", "Add cross-compilation target");
    printCommand("target list", "", "List available targets");
    printCommand("target remove", "<triple>", "Remove a target");
    std.debug.print("\n", .{});

    color.yellow("DEPENDENCY COMMANDS:\n", .{});
    printCommand("deps init", "", "Initialize dependency manifest");
    printCommand("deps add", "<spec>", "Add a dependency");
    printCommand("deps fetch", "", "Fetch and cache dependencies");
    printCommand("deps graph", "", "Show dependency graph");
    std.debug.print("\n", .{});

    color.yellow("CACHE COMMANDS:\n", .{});
    printCommand("cache status", "", "Show cache statistics");
    printCommand("cache prune", "[--dry-run]", "Prune unused cache entries");
    printCommand("cache doctor", "", "Verify cache integrity");
    std.debug.print("\n", .{});

    color.yellow("POLICY COMMANDS:\n", .{});
    printCommand("policy audit", "", "Audit dependencies against policy");
    printCommand("verify", "", "Verify project integrity");
    std.debug.print("\n", .{});

    color.yellow("UTILITY COMMANDS:\n", .{});
    printCommand("doctor", "", "Run system diagnostics");
    printCommand("ci bootstrap", "", "Generate CI configuration");
    printCommand("version", "", "Show version information");
    printCommand("help", "", "Show this help message");
    std.debug.print("\n", .{});

    color.yellow("GLOBAL OPTIONS:\n", .{});
    std.debug.print("    --json                     Output in JSON format\n", .{});
    std.debug.print("    --verbose, -v              Verbose output\n", .{});
    std.debug.print("    --quiet, -q                Minimal output\n", .{});
    std.debug.print("    --cache-dir <dir>          Override cache directory\n", .{});
    std.debug.print("    --config <file>            Use specific config file\n", .{});
    std.debug.print("    --help, -h                 Show help\n", .{});
    std.debug.print("    --version                  Show version\n\n", .{});

    color.yellow("EXAMPLES:\n", .{});
    std.debug.print("    ", .{});
    color.green("zim install 0.16.0", .{});
    std.debug.print("         Install Zig 0.16.0\n", .{});
    std.debug.print("    ", .{});
    color.green("zim use 0.16.0", .{});
    std.debug.print("             Switch to Zig 0.16.0\n", .{});
    std.debug.print("    ", .{});
    color.green("zim deps add /data/projects/zsync", .{});
    std.debug.print("\n", .{});
    std.debug.print("    ", .{});
    color.green("zim target add wasm32-wasi", .{});
    std.debug.print("\n", .{});
    std.debug.print("    ", .{});
    color.green("zim verify --json", .{});
    std.debug.print("\n\n", .{});

    std.debug.print("For more information, visit: ", .{});
    color.cyan("https://github.com/ghostkellz/zim", .{});
    std.debug.print("\n\n", .{});
}

fn printCommand(cmd: []const u8, args: []const u8, description: []const u8) void {
    std.debug.print("    ", .{});
    color.green("{s}", .{cmd});
    if (args.len > 0) {
        std.debug.print(" ", .{});
        color.cyan("{s}", .{args});
    }

    // Calculate padding for alignment
    const cmd_len = cmd.len + args.len + if (args.len > 0) @as(usize, 1) else 0;
    const padding = if (cmd_len < 26) 26 - cmd_len else 2;
    var i: usize = 0;
    while (i < padding) : (i += 1) {
        std.debug.print(" ", .{});
    }

    std.debug.print("{s}\n", .{description});
}
