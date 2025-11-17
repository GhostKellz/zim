const std = @import("std");
const color = @import("../util/color.zig");

/// Generate shell completion scripts
pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try printHelp();
        return;
    }

    const shell = args[0];

    if (std.mem.eql(u8, shell, "bash")) {
        try generateBashCompletions();
    } else if (std.mem.eql(u8, shell, "zsh")) {
        try generateZshCompletions();
    } else if (std.mem.eql(u8, shell, "fish")) {
        try generateFishCompletions();
    } else if (std.mem.eql(u8, shell, "--install")) {
        try installCompletions(allocator);
    } else {
        color.error_("Unknown shell: {s}\n", .{shell});
        color.dim("Supported shells: bash, zsh, fish\n", .{});
        return error.UnknownShell;
    }
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\Usage: zim completions <SHELL>
        \\
        \\Generate shell completion scripts
        \\
        \\Shells:
        \\  bash               Generate Bash completions
        \\  zsh                Generate Zsh completions
        \\  fish               Generate Fish completions
        \\  --install          Auto-install for current shell
        \\
        \\Examples:
        \\  zim completions bash > /usr/local/etc/bash_completion.d/zim
        \\  zim completions zsh > ~/.zsh/completions/_zim
        \\  zim completions fish > ~/.config/fish/completions/zim.fish
        \\  zim completions --install
        \\
    );
}

fn generateBashCompletions() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\# Bash completion for ZIM package manager
        \\# Source this file or install to /usr/local/etc/bash_completion.d/
        \\
        \\_zim_completions() {
        \\    local cur prev opts
        \\    COMPREPLY=()
        \\    cur="${COMP_WORDS[COMP_CWORD]}"
        \\    prev="${COMP_WORDS[COMP_CWORD-1]}"
        \\
        \\    # Main commands
        \\    local commands="init build test clean install remove update search deps toolchain cache doctor watch why outdated vendor config completions help"
        \\
        \\    # If we're completing the first argument
        \\    if [[ ${COMP_CWORD} -eq 1 ]]; then
        \\        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
        \\        return 0
        \\    fi
        \\
        \\    # Command-specific completions
        \\    case "${COMP_WORDS[1]}" in
        \\        init)
        \\            local opts="--name --version --lib --exe --help"
        \\            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        \\            ;;
        \\        build)
        \\            local opts="--release --target --verbose --help"
        \\            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        \\            ;;
        \\        test)
        \\            local opts="--filter --verbose --help"
        \\            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        \\            ;;
        \\        deps)
        \\            local subcmds="fetch tree graph update export"
        \\            COMPREPLY=( $(compgen -W "${subcmds}" -- ${cur}) )
        \\            ;;
        \\        toolchain)
        \\            local subcmds="list install remove update default available"
        \\            COMPREPLY=( $(compgen -W "${subcmds}" -- ${cur}) )
        \\            ;;
        \\        cache)
        \\            local subcmds="clean size list verify rebuild"
        \\            COMPREPLY=( $(compgen -W "${subcmds}" -- ${cur}) )
        \\            ;;
        \\        watch)
        \\            local opts="--command --no-clear --debounce --help"
        \\            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        \\            ;;
        \\        completions)
        \\            local shells="bash zsh fish --install"
        \\            COMPREPLY=( $(compgen -W "${shells}" -- ${cur}) )
        \\            ;;
        \\        *)
        \\            COMPREPLY=()
        \\            ;;
        \\    esac
        \\}
        \\
        \\complete -F _zim_completions zim
        \\
    );
}

fn generateZshCompletions() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\#compdef zim
        \\# Zsh completion for ZIM package manager
        \\# Install to ~/.zsh/completions/_zim or /usr/local/share/zsh/site-functions/_zim
        \\
        \\_zim() {
        \\    local -a commands
        \\    commands=(
        \\        'init:Initialize a new Zig project'
        \\        'build:Build the project'
        \\        'test:Run tests'
        \\        'clean:Clean build artifacts'
        \\        'install:Install dependencies'
        \\        'remove:Remove a dependency'
        \\        'update:Update dependencies'
        \\        'search:Search for packages'
        \\        'deps:Manage dependencies'
        \\        'toolchain:Manage Zig toolchains'
        \\        'cache:Manage package cache'
        \\        'doctor:Diagnose issues'
        \\        'watch:Watch for changes and rebuild'
        \\        'why:Explain dependency chains'
        \\        'outdated:Check for outdated dependencies'
        \\        'vendor:Vendor dependencies for offline builds'
        \\        'config:Manage configuration'
        \\        'completions:Generate shell completions'
        \\        'help:Show help information'
        \\    )
        \\
        \\    local -a init_opts
        \\    init_opts=(
        \\        '--name[Project name]:name:'
        \\        '--version[Project version]:version:'
        \\        '--lib[Create library project]'
        \\        '--exe[Create executable project]'
        \\        '--help[Show help]'
        \\    )
        \\
        \\    local -a build_opts
        \\    build_opts=(
        \\        '--release[Build in release mode]'
        \\        '--target[Build target]:target:'
        \\        '--verbose[Verbose output]'
        \\        '--help[Show help]'
        \\    )
        \\
        \\    local -a watch_opts
        \\    watch_opts=(
        \\        '--command[Command to run]:command:'
        \\        '--no-clear[Do not clear screen]'
        \\        '--debounce[Debounce delay]:milliseconds:'
        \\        '--help[Show help]'
        \\    )
        \\
        \\    local -a deps_cmds
        \\    deps_cmds=(
        \\        'fetch:Fetch dependencies'
        \\        'tree:Show dependency tree'
        \\        'graph:Generate dependency graph'
        \\        'update:Update dependencies'
        \\        'export:Export to build.zig.zon'
        \\    )
        \\
        \\    local -a toolchain_cmds
        \\    toolchain_cmds=(
        \\        'list:List installed toolchains'
        \\        'install:Install a toolchain'
        \\        'remove:Remove a toolchain'
        \\        'update:Update toolchains'
        \\        'default:Set default toolchain'
        \\        'available:Show available toolchains'
        \\    )
        \\
        \\    local -a cache_cmds
        \\    cache_cmds=(
        \\        'clean:Clean cache'
        \\        'size:Show cache size'
        \\        'list:List cached packages'
        \\        'verify:Verify cache integrity'
        \\        'rebuild:Rebuild cache'
        \\    )
        \\
        \\    local -a completions_shells
        \\    completions_shells=(
        \\        'bash:Generate Bash completions'
        \\        'zsh:Generate Zsh completions'
        \\        'fish:Generate Fish completions'
        \\        '--install:Auto-install for current shell'
        \\    )
        \\
        \\    _arguments -C \
        \\        '1: :->command' \
        \\        '*:: :->args'
        \\
        \\    case $state in
        \\        command)
        \\            _describe 'zim command' commands
        \\            ;;
        \\        args)
        \\            case ${words[1]} in
        \\                init)
        \\                    _arguments $init_opts
        \\                    ;;
        \\                build)
        \\                    _arguments $build_opts
        \\                    ;;
        \\                watch)
        \\                    _arguments $watch_opts
        \\                    ;;
        \\                deps)
        \\                    _describe 'deps subcommand' deps_cmds
        \\                    ;;
        \\                toolchain)
        \\                    _describe 'toolchain subcommand' toolchain_cmds
        \\                    ;;
        \\                cache)
        \\                    _describe 'cache subcommand' cache_cmds
        \\                    ;;
        \\                completions)
        \\                    _describe 'shell' completions_shells
        \\                    ;;
        \\            esac
        \\            ;;
        \\    esac
        \\}
        \\
        \\_zim "$@"
        \\
    );
}

fn generateFishCompletions() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\# Fish completion for ZIM package manager
        \\# Install to ~/.config/fish/completions/zim.fish
        \\
        \\# Main commands
        \\complete -c zim -f -n "__fish_use_subcommand" -a "init" -d "Initialize a new Zig project"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "build" -d "Build the project"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "test" -d "Run tests"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "clean" -d "Clean build artifacts"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "install" -d "Install dependencies"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "remove" -d "Remove a dependency"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "update" -d "Update dependencies"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "search" -d "Search for packages"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "deps" -d "Manage dependencies"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "toolchain" -d "Manage Zig toolchains"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "cache" -d "Manage package cache"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "doctor" -d "Diagnose issues"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "watch" -d "Watch for changes and rebuild"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "why" -d "Explain dependency chains"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "outdated" -d "Check for outdated dependencies"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "vendor" -d "Vendor dependencies for offline builds"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "config" -d "Manage configuration"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "completions" -d "Generate shell completions"
        \\complete -c zim -f -n "__fish_use_subcommand" -a "help" -d "Show help information"
        \\
        \\# init options
        \\complete -c zim -n "__fish_seen_subcommand_from init" -l "name" -d "Project name" -r
        \\complete -c zim -n "__fish_seen_subcommand_from init" -l "version" -d "Project version" -r
        \\complete -c zim -n "__fish_seen_subcommand_from init" -l "lib" -d "Create library project"
        \\complete -c zim -n "__fish_seen_subcommand_from init" -l "exe" -d "Create executable project"
        \\complete -c zim -n "__fish_seen_subcommand_from init" -l "help" -d "Show help"
        \\
        \\# build options
        \\complete -c zim -n "__fish_seen_subcommand_from build" -l "release" -d "Build in release mode"
        \\complete -c zim -n "__fish_seen_subcommand_from build" -l "target" -d "Build target" -r
        \\complete -c zim -n "__fish_seen_subcommand_from build" -l "verbose" -d "Verbose output"
        \\complete -c zim -n "__fish_seen_subcommand_from build" -l "help" -d "Show help"
        \\
        \\# watch options
        \\complete -c zim -n "__fish_seen_subcommand_from watch" -s "c" -l "command" -d "Command to run" -r
        \\complete -c zim -n "__fish_seen_subcommand_from watch" -l "no-clear" -d "Don't clear screen"
        \\complete -c zim -n "__fish_seen_subcommand_from watch" -l "debounce" -d "Debounce delay (ms)" -r
        \\complete -c zim -n "__fish_seen_subcommand_from watch" -s "h" -l "help" -d "Show help"
        \\
        \\# deps subcommands
        \\complete -c zim -n "__fish_seen_subcommand_from deps" -f -a "fetch" -d "Fetch dependencies"
        \\complete -c zim -n "__fish_seen_subcommand_from deps" -f -a "tree" -d "Show dependency tree"
        \\complete -c zim -n "__fish_seen_subcommand_from deps" -f -a "graph" -d "Generate dependency graph"
        \\complete -c zim -n "__fish_seen_subcommand_from deps" -f -a "update" -d "Update dependencies"
        \\complete -c zim -n "__fish_seen_subcommand_from deps" -f -a "export" -d "Export to build.zig.zon"
        \\
        \\# toolchain subcommands
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "list" -d "List installed toolchains"
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "install" -d "Install a toolchain"
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "remove" -d "Remove a toolchain"
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "update" -d "Update toolchains"
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "default" -d "Set default toolchain"
        \\complete -c zim -n "__fish_seen_subcommand_from toolchain" -f -a "available" -d "Show available toolchains"
        \\
        \\# cache subcommands
        \\complete -c zim -n "__fish_seen_subcommand_from cache" -f -a "clean" -d "Clean cache"
        \\complete -c zim -n "__fish_seen_subcommand_from cache" -f -a "size" -d "Show cache size"
        \\complete -c zim -n "__fish_seen_subcommand_from cache" -f -a "list" -d "List cached packages"
        \\complete -c zim -n "__fish_seen_subcommand_from cache" -f -a "verify" -d "Verify cache integrity"
        \\complete -c zim -n "__fish_seen_subcommand_from cache" -f -a "rebuild" -d "Rebuild cache"
        \\
        \\# completions shells
        \\complete -c zim -n "__fish_seen_subcommand_from completions" -f -a "bash" -d "Generate Bash completions"
        \\complete -c zim -n "__fish_seen_subcommand_from completions" -f -a "zsh" -d "Generate Zsh completions"
        \\complete -c zim -n "__fish_seen_subcommand_from completions" -f -a "fish" -d "Generate Fish completions"
        \\complete -c zim -n "__fish_seen_subcommand_from completions" -f -a "--install" -d "Auto-install for current shell"
        \\
    );
}

fn installCompletions(allocator: std.mem.Allocator) !void {
    const shell = std.posix.getenv("SHELL") orelse {
        color.error_("Could not detect shell from $SHELL\n", .{});
        return error.ShellNotDetected;
    };

    color.info("Detected shell: {s}\n", .{shell});

    if (std.mem.indexOf(u8, shell, "bash") != null) {
        try installBashCompletions(allocator);
    } else if (std.mem.indexOf(u8, shell, "zsh") != null) {
        try installZshCompletions(allocator);
    } else if (std.mem.indexOf(u8, shell, "fish") != null) {
        try installFishCompletions(allocator);
    } else {
        color.error_("Unsupported shell: {s}\n", .{shell});
        color.dim("Manually install completions using:\n", .{});
        color.dim("  zim completions bash > /path/to/completions\n", .{});
        return error.UnsupportedShell;
    }
}

fn installBashCompletions(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.local/share/bash-completion/completions", .{home});
    defer allocator.free(completion_dir);

    std.fs.cwd().makePath(completion_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const completion_file = try std.fmt.allocPrint(allocator, "{s}/zim", .{completion_dir});
    defer allocator.free(completion_file);

    const file = try std.fs.cwd().createFile(completion_file, .{});
    defer file.close();

    // Redirect stdout to file temporarily
    const old_stdout = std.io.getStdOut();
    try std.io.setStdOut(file);
    try generateBashCompletions();
    try std.io.setStdOut(old_stdout);

    color.success("✅ Bash completions installed to: {s}\n", .{completion_file});
    color.dim("   Restart your shell or run: source {s}\n", .{completion_file});
}

fn installZshCompletions(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.zsh/completions", .{home});
    defer allocator.free(completion_dir);

    std.fs.cwd().makePath(completion_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const completion_file = try std.fmt.allocPrint(allocator, "{s}/_zim", .{completion_dir});
    defer allocator.free(completion_file);

    const file = try std.fs.cwd().createFile(completion_file, .{});
    defer file.close();

    const old_stdout = std.io.getStdOut();
    try std.io.setStdOut(file);
    try generateZshCompletions();
    try std.io.setStdOut(old_stdout);

    color.success("✅ Zsh completions installed to: {s}\n", .{completion_file});
    color.dim("   Add to ~/.zshrc: fpath=({s} $fpath)\n", .{completion_dir});
    color.dim("   Then run: autoload -U compinit && compinit\n", .{});
}

fn installFishCompletions(allocator: std.mem.Allocator) !void {
    const home = std.posix.getenv("HOME") orelse "/tmp";
    const completion_dir = try std.fmt.allocPrint(allocator, "{s}/.config/fish/completions", .{home});
    defer allocator.free(completion_dir);

    std.fs.cwd().makePath(completion_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const completion_file = try std.fmt.allocPrint(allocator, "{s}/zim.fish", .{completion_dir});
    defer allocator.free(completion_file);

    const file = try std.fs.cwd().createFile(completion_file, .{});
    defer file.close();

    const old_stdout = std.io.getStdOut();
    try std.io.setStdOut(file);
    try generateFishCompletions();
    try std.io.setStdOut(old_stdout);

    color.success("✅ Fish completions installed to: {s}\n", .{completion_file});
    color.dim("   Completions will be available in new fish sessions\n", .{});
}
