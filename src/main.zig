const std = @import("std");
const cli = @import("cli/cli.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Use the cli router
    const exit_code = cli.run(allocator, args) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return err;
    };

    std.process.exit(exit_code);
}
