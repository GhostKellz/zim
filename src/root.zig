//! ZIM - Zig Infrastructure Manager
//! Root module that exposes the public API

const std = @import("std");

// Export public modules
pub const cli = @import("cli/cli.zig");
pub const config = @import("config/config.zig");
pub const toolchain = @import("toolchain/toolchain.zig");
pub const deps = @import("deps/deps.zig");
pub const target = @import("target/target.zig");

// Export utility modules
pub const util = struct {
    pub const version = @import("util/version.zig");
    pub const download = @import("util/download.zig");
    pub const color = @import("util/color.zig");
};

// Version info
pub const version = "0.1.0-dev";
pub const zig_version_string = @import("builtin").zig_version_string;

test {
    std.testing.refAllDecls(@This());
}
