const std = @import("std");
const flare = @import("flare");

/// ANSI color codes for terminal output
pub const Color = enum {
    reset,
    bold,
    dim,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    gray,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .gray => "\x1b[90m",
        };
    }
};

/// Check if ANSI colors should be enabled
pub fn isColorEnabled() bool {
    // Check NO_COLOR environment variable (https://no-color.org/)
    if (std.posix.getenv("NO_COLOR")) |_| {
        return false;
    }

    // Check TERM environment variable
    if (std.posix.getenv("TERM")) |term| {
        if (std.mem.eql(u8, term, "dumb")) {
            return false;
        }
    }

    // Check if stdout is a TTY
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) {
        return false; // Simplified for now
    }

    // On Unix-like systems, check if fd 1 (stdout) is a tty
    const stdout_fd = std.posix.STDOUT_FILENO;
    return std.posix.isatty(stdout_fd);
}

/// Global color enable/disable flag (set once at startup)
var color_enabled: bool = undefined;
var color_initialized: bool = false;

pub fn init() void {
    if (!color_initialized) {
        color_enabled = isColorEnabled();
        color_initialized = true;
    }
}

/// Print colored text
pub fn print(comptime fmt: []const u8, args: anytype, color: Color) void {
    init();
    if (color_enabled) {
        std.debug.print("{s}" ++ fmt ++ "{s}", .{color.code()} ++ args ++ .{Color.reset.code()});
    } else {
        std.debug.print(fmt, args);
    }
}

/// Print with multiple colors in format
pub fn printColored(comptime fmt: []const u8, args: anytype) void {
    init();
    if (color_enabled) {
        std.debug.print(fmt, args);
    } else {
        // Strip ANSI codes
        std.debug.print(fmt, args);
    }
}

/// Convenience functions for common use cases
pub fn success(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .green);
}

pub fn error_(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .red);
}

pub fn warning(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .yellow);
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .cyan);
}

pub fn bold(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .bold);
}

pub fn dim(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .dim);
}

// Color-specific functions
pub fn red(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .red);
}

pub fn green(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .green);
}

pub fn yellow(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .yellow);
}

pub fn blue(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .blue);
}

pub fn magenta(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .magenta);
}

pub fn cyan(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .cyan);
}

pub fn white(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .white);
}

pub fn gray(comptime fmt: []const u8, args: anytype) void {
    print(fmt, args, .gray);
}
