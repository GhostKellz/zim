const std = @import("std");
const color = @import("color.zig");

/// Smart error handler that provides contextual suggestions
pub const ErrorSuggestion = struct {
    error_type: []const u8,
    message: []const u8,
    suggestions: []const []const u8,
    help_command: ?[]const u8 = null,

    pub fn print(self: ErrorSuggestion) void {
        color.error_("\n❌ {s}\n", .{self.error_type});
        color.dim("   {s}\n\n", .{self.message});

        if (self.suggestions.len > 0) {
            color.info("💡 Suggestions:\n", .{});
            for (self.suggestions) |suggestion| {
                color.dim("   • {s}\n", .{suggestion});
            }
        }

        if (self.help_command) |cmd| {
            color.info("\n🔗 Learn more: \x1B[36m{s}\x1B[0m\n", .{cmd});
        }

        std.debug.print("\n", .{});
    }
};

/// Analyze error and provide helpful suggestions
pub fn suggestForError(allocator: std.mem.Allocator, err: anyerror, context: []const u8) !ErrorSuggestion {
    _ = allocator;

    return switch (err) {
        error.FileNotFound => fileNotFoundSuggestion(context),
        error.PermissionDenied => permissionDeniedSuggestion(context),
        error.NetworkUnreachable, error.ConnectionRefused => networkErrorSuggestion(context),
        error.OutOfMemory => outOfMemorySuggestion(),
        error.InvalidCharacter, error.InvalidUtf8 => invalidDataSuggestion(context),
        else => genericErrorSuggestion(err, context),
    };
}

fn fileNotFoundSuggestion(context: []const u8) ErrorSuggestion {
    const is_build_file = std.mem.indexOf(u8, context, "build.zig") != null;
    const is_zon_file = std.mem.indexOf(u8, context, ".zon") != null;
    const is_config = std.mem.indexOf(u8, context, "config") != null or
        std.mem.indexOf(u8, context, ".toml") != null;

    if (is_build_file) {
        return .{
            .error_type = "File Not Found",
            .message = context,
            .suggestions = &[_][]const u8{
                "This directory doesn't appear to be a Zig project",
                "Run 'zim init' to create a new project",
                "Or navigate to an existing project directory",
            },
            .help_command = "zim init --help",
        };
    } else if (is_zon_file) {
        return .{
            .error_type = "build.zig.zon Not Found",
            .message = context,
            .suggestions = &[_][]const u8{
                "Your project is missing a build.zig.zon file",
                "This file defines your project dependencies",
                "Run 'zim init' to generate one",
            },
            .help_command = "zim deps --help",
        };
    } else if (is_config) {
        return .{
            .error_type = "Configuration File Not Found",
            .message = context,
            .suggestions = &[_][]const u8{
                "ZIM couldn't find your configuration file",
                "Run 'zim config init' to create one",
                "Or use default configuration",
            },
            .help_command = "zim config --help",
        };
    }

    return .{
        .error_type = "File Not Found",
        .message = context,
        .suggestions = &[_][]const u8{
            "Check that the file path is correct",
            "Verify the file exists in your project",
            "Try using an absolute path instead",
        },
        .help_command = null,
    };
}

fn permissionDeniedSuggestion(context: []const u8) ErrorSuggestion {
    const is_cache = std.mem.indexOf(u8, context, "cache") != null or
        std.mem.indexOf(u8, context, ".zim") != null;

    if (is_cache) {
        return .{
            .error_type = "Permission Denied",
            .message = context,
            .suggestions = &[_][]const u8{
                "ZIM doesn't have permission to access the cache directory",
                "Try running: chmod -R u+rw ~/.zim/cache",
                "Or set ZIM_CACHE_DIR to a writable location",
            },
            .help_command = "zim config --help",
        };
    }

    return .{
        .error_type = "Permission Denied",
        .message = context,
        .suggestions = &[_][]const u8{
            "You don't have permission to access this file/directory",
            "Check file permissions with: ls -la",
            "Try running with appropriate permissions",
        },
        .help_command = null,
    };
}

fn networkErrorSuggestion(context: []const u8) ErrorSuggestion {
    const is_download = std.mem.indexOf(u8, context, "download") != null or
        std.mem.indexOf(u8, context, "fetch") != null;

    if (is_download) {
        return .{
            .error_type = "Network Error",
            .message = context,
            .suggestions = &[_][]const u8{
                "Check your internet connection",
                "Verify you can access the package registry",
                "Try again later if the service is down",
                "Use 'zim doctor' to diagnose network issues",
            },
            .help_command = "zim doctor",
        };
    }

    return .{
        .error_type = "Network Error",
        .message = context,
        .suggestions = &[_][]const u8{
            "Check your network connection",
            "Verify firewall settings",
            "Try using a VPN if blocked",
        },
        .help_command = "zim doctor",
    };
}

fn outOfMemorySuggestion() ErrorSuggestion {
    return .{
        .error_type = "Out of Memory",
        .message = "ZIM ran out of memory during operation",
        .suggestions = &[_][]const u8{
            "Close other applications to free up RAM",
            "Try building with fewer parallel jobs",
            "Clear cache: zim cache clean",
            "Increase system swap space",
        },
        .help_command = "zim cache --help",
    };
}

fn invalidDataSuggestion(context: []const u8) ErrorSuggestion {
    const is_manifest = std.mem.indexOf(u8, context, ".zon") != null or
        std.mem.indexOf(u8, context, ".toml") != null;

    if (is_manifest) {
        return .{
            .error_type = "Invalid File Format",
            .message = context,
            .suggestions = &[_][]const u8{
                "The manifest file contains invalid syntax",
                "Check for syntax errors in your build.zig.zon",
                "Validate the file format matches Zig syntax",
                "Try regenerating with 'zim init --force'",
            },
            .help_command = "zim doctor",
        };
    }

    return .{
        .error_type = "Invalid Data",
        .message = context,
        .suggestions = &[_][]const u8{
            "The file contains invalid or corrupted data",
            "Check file encoding (should be UTF-8)",
            "Try re-downloading or regenerating the file",
        },
        .help_command = null,
    };
}

fn genericErrorSuggestion(err: anyerror, context: []const u8) ErrorSuggestion {
    const err_name = @errorName(err);

    return .{
        .error_type = err_name,
        .message = context,
        .suggestions = &[_][]const u8{
            "Run 'zim doctor' to diagnose common issues",
            "Check ZIM's GitHub issues for similar problems",
            "Try with verbose logging: zim --verbose <command>",
        },
        .help_command = "zim doctor",
    };
}

/// Common error patterns and their fixes
pub const CommonErrors = struct {
    /// Dependency not found
    pub fn dependencyNotFound(allocator: std.mem.Allocator, dep_name: []const u8) !ErrorSuggestion {
        const message = try std.fmt.allocPrint(
            allocator,
            "Dependency '{s}' not found in registry",
            .{dep_name},
        );

        return .{
            .error_type = "Dependency Not Found",
            .message = message,
            .suggestions = &[_][]const u8{
                "Check the package name spelling",
                "Search available packages: zim search <name>",
                "Update package index: zim update",
                "The package might not be published yet",
            },
            .help_command = "zim search",
        };
    }

    /// Version conflict
    pub fn versionConflict(
        allocator: std.mem.Allocator,
        pkg: []const u8,
        v1: []const u8,
        v2: []const u8,
    ) !ErrorSuggestion {
        const message = try std.fmt.allocPrint(
            allocator,
            "Version conflict: {s} requires both {s} and {s}",
            .{ pkg, v1, v2 },
        );

        return .{
            .error_type = "Version Conflict",
            .message = message,
            .suggestions = &[_][]const u8{
                "Update dependency versions to be compatible",
                "Use version ranges instead of exact versions",
                "Run 'zim why <package>' to see dependency chain",
                "Consider using a different package combination",
            },
            .help_command = "zim why",
        };
    }

    /// Build failed
    pub fn buildFailed(allocator: std.mem.Allocator, error_msg: []const u8) !ErrorSuggestion {
        const is_compile_error = std.mem.indexOf(u8, error_msg, "error:") != null;
        const is_linker_error = std.mem.indexOf(u8, error_msg, "lld:") != null or
            std.mem.indexOf(u8, error_msg, "ld:") != null;

        if (is_compile_error) {
            const message = try std.fmt.allocPrint(
                allocator,
                "Compilation failed:\n{s}",
                .{error_msg},
            );

            return .{
                .error_type = "Build Failed - Compilation Error",
                .message = message,
                .suggestions = &[_][]const u8{
                    "Fix the compilation errors in your code",
                    "Check Zig version compatibility: zim doctor",
                    "Ensure dependencies are up to date: zim deps fetch",
                    "Try cleaning build cache: zig build clean",
                },
                .help_command = "zim doctor",
            };
        } else if (is_linker_error) {
            const message = try std.fmt.allocPrint(
                allocator,
                "Linking failed:\n{s}",
                .{error_msg},
            );

            return .{
                .error_type = "Build Failed - Linker Error",
                .message = message,
                .suggestions = &[_][]const u8{
                    "Check for missing system libraries",
                    "Verify target platform is supported",
                    "Install required development packages",
                    "Try: sudo apt install build-essential (Linux)",
                },
                .help_command = "zim doctor",
            };
        }

        return .{
            .error_type = "Build Failed",
            .message = error_msg,
            .suggestions = &[_][]const u8{
                "Check build.zig for configuration issues",
                "Ensure all dependencies are installed",
                "Try cleaning and rebuilding",
                "Run with verbose output: zig build --verbose",
            },
            .help_command = "zim doctor",
        };
    }

    /// Toolchain not found
    pub fn toolchainNotFound(allocator: std.mem.Allocator, version: []const u8) !ErrorSuggestion {
        const message = try std.fmt.allocPrint(
            allocator,
            "Zig toolchain {s} not installed",
            .{version},
        );

        return .{
            .error_type = "Toolchain Not Found",
            .message = message,
            .suggestions = &[_][]const u8{
                "Install the required Zig version: zim install",
                "List available toolchains: zim toolchain list",
                "Update project to use installed version",
                "Check available versions: zim toolchain available",
            },
            .help_command = "zim toolchain --help",
        };
    }

    /// Cache corrupted
    pub fn cacheCorrupted() ErrorSuggestion {
        return .{
            .error_type = "Cache Corrupted",
            .message = "Package cache appears to be corrupted",
            .suggestions = &[_][]const u8{
                "Clean the cache: zim cache clean",
                "Re-fetch dependencies: zim deps fetch --force",
                "Check cache integrity: zim doctor",
                "Verify disk space is available",
            },
            .help_command = "zim cache --help",
        };
    }
};

/// Pretty print errors with suggestions
pub fn printError(err: anyerror, context: []const u8) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const suggestion = suggestForError(allocator, err, context) catch {
        // Fallback to simple error
        color.error_("\n❌ Error: {}\n", .{err});
        color.dim("   {s}\n\n", .{context});
        return;
    };

    suggestion.print();
}

test "error suggestions" {
    const allocator = std.testing.allocator;

    const suggestion = try suggestForError(allocator, error.FileNotFound, "build.zig");
    try std.testing.expect(suggestion.suggestions.len > 0);
}
