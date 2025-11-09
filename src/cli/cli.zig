const std = @import("std");
const builtin = @import("builtin");
const config_mod = @import("../config/config.zig");
const toolchain_mod = @import("../toolchain/toolchain.zig");
const deps_mod = @import("../deps/deps.zig");
const target_mod = @import("../target/target.zig");

/// Command represents all available ZIM commands
pub const Command = enum {
    // Toolchain commands
    toolchain,
    install, // shorthand for toolchain install
    use, // shorthand for toolchain use

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

    // Target subcommands
    add,
    remove,

    // Deps subcommands
    init,
    fetch,
    graph,

    // Cache subcommands
    status,
    prune,
    doctor,

    // Policy subcommands
    audit,

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
            subcommand = parseSubCommand(arg) catch {
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
    if (needsSubCommand(command.?) and subcommand == null) {
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
        .{ "target", .target },
        .{ "deps", .deps },
        .{ "cache", .cache },
        .{ "policy", .policy },
        .{ "verify", .verify },
        .{ "doctor", .doctor },
        .{ "version", .version },
        .{ "help", .help },
        .{ "mcp", .mcp },
        .{ "ci", .ci },
    });

    return commands.get(cmd) orelse CommandError.UnknownCommand;
}

fn parseSubCommand(cmd: []const u8) !SubCommand {
    const subcommands = std.StaticStringMap(SubCommand).initComptime(.{
        .{ "install", .install },
        .{ "use", .use_cmd },
        .{ "pin", .pin },
        .{ "list", .list },
        .{ "add", .add },
        .{ "remove", .remove },
        .{ "init", .init },
        .{ "fetch", .fetch },
        .{ "graph", .graph },
        .{ "status", .status },
        .{ "prune", .prune },
        .{ "doctor", .doctor },
        .{ "audit", .audit },
        .{ "bootstrap", .bootstrap },
    });

    return subcommands.get(cmd) orelse CommandError.UnknownSubCommand;
}

fn needsSubCommand(cmd: Command) bool {
    return switch (cmd) {
        .toolchain, .target, .deps, .cache, .policy, .ci => true,
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
        .target => executeTargetCommand(allocator, parsed),
        .deps => executeDepsCommand(allocator, parsed),
        .cache => executeCacheCommand(allocator, parsed),
        .policy => executePolicyCommand(allocator, parsed),
        .verify => executeVerifyCommand(allocator, parsed),
        .doctor => executeDoctorCommand(allocator, parsed),
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
        .add => {
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
        .remove => {
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
        .add => {
            if (parsed.args.len == 0) {
                std.debug.print("Error: Missing dependency specification\n", .{});
                std.debug.print("Usage: zim deps add <name> [--git <url> --ref <ref>]\n", .{});
                std.debug.print("       zim deps add <name> [--tarball <url> --hash <hash>]\n", .{});
                std.debug.print("       zim deps add <name> [--local <path>]\n", .{});
                return 1;
            }

            // Parse dependency specification
            // TODO: Implement full arg parsing for git/tarball/local sources
            std.debug.print("Adding dependency: {s}\n", .{parsed.args[0]});
            std.debug.print("(Full dependency addition not yet implemented)\n", .{});
            std.debug.print("Please manually edit zim.toml to add dependencies\n", .{});
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
        else => {
            std.debug.print("Error: Invalid subcommand for 'deps'\n", .{});
            std.debug.print("Available subcommands: init, add, fetch, graph\n", .{});
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
        .doctor => {
            std.debug.print("Running cache diagnostics...\n", .{});
            std.debug.print("  Cache directory: {s}\n", .{config.getCacheDir()});
            // TODO: Verify cache integrity
            std.debug.print("(Cache verification not yet implemented)\n", .{});
            return 0;
        },
        else => {
            std.debug.print("Error: Invalid subcommand for 'cache'\n", .{});
            std.debug.print("Available subcommands: status, prune, doctor\n", .{});
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
    _ = allocator;
    _ = parsed;
    std.debug.print("Running ZIM diagnostics...\n", .{});
    std.debug.print("\nChecking TLS/CA configuration...\n", .{});
    std.debug.print("Checking network connectivity...\n", .{});
    std.debug.print("Checking toolchain installations...\n", .{});
    // TODO: Implement comprehensive health checks
    std.debug.print("(Not yet implemented)\n", .{});
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

fn printVersion() void {
    std.debug.print("zim 0.1.0-dev\n", .{});
    std.debug.print("Zig Infrastructure Manager\n", .{});
    std.debug.print("Zig version: {s}\n", .{builtin.zig_version_string});
}

fn printHelp() void {
    const message =
        \\zim - Zig Infrastructure Manager
        \\
        \\USAGE:
        \\    zim <COMMAND> [OPTIONS]
        \\
        \\TOOLCHAIN COMMANDS:
        \\    toolchain install <ver>    Install a Zig toolchain version
        \\    toolchain use <ver>        Set global Zig version
        \\    toolchain pin <ver>        Pin project to specific Zig version
        \\    toolchain list             List installed toolchains
        \\    install <ver>              Shorthand for 'toolchain install'
        \\    use <ver>                  Shorthand for 'toolchain use'
        \\
        \\TARGET COMMANDS:
        \\    target add <triple>        Add cross-compilation target
        \\    target list                List available targets
        \\    target remove <triple>     Remove a target
        \\
        \\DEPENDENCY COMMANDS:
        \\    deps init                  Initialize dependency manifest
        \\    deps add <spec>            Add a dependency
        \\    deps fetch                 Fetch and cache dependencies
        \\    deps graph                 Show dependency graph
        \\
        \\CACHE COMMANDS:
        \\    cache status               Show cache statistics
        \\    cache prune [--dry-run]    Prune unused cache entries
        \\    cache doctor               Verify cache integrity
        \\
        \\POLICY COMMANDS:
        \\    policy audit               Audit dependencies against policy
        \\    verify                     Verify project integrity
        \\
        \\UTILITY COMMANDS:
        \\    doctor                     Run system diagnostics
        \\    ci bootstrap               Generate CI configuration
        \\    version                    Show version information
        \\    help                       Show this help message
        \\
        \\GLOBAL OPTIONS:
        \\    --json                     Output in JSON format
        \\    --verbose, -v              Verbose output
        \\    --quiet, -q                Minimal output
        \\    --cache-dir <dir>          Override cache directory
        \\    --config <file>            Use specific config file
        \\    --help, -h                 Show help
        \\    --version                  Show version
        \\
        \\EXAMPLES:
        \\    zim install 0.16.0         Install Zig 0.16.0
        \\    zim use 0.16.0             Switch to Zig 0.16.0
        \\    zim deps add /data/projects/zsync
        \\    zim target add wasm32-wasi
        \\    zim verify --json
        \\
        \\For more information, visit: https://github.com/ghostkellz/zim
        \\
    ;

    std.debug.print("{s}", .{message});
}
