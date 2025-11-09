const std = @import("std");
const cli = @import("cli/cli.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const exit_code = cli.run(allocator, args) catch |err| switch (err) {
        error.OutOfMemory => {
            std.debug.print("Error: Out of memory\n", .{});
            return err;
        },
        error.UnknownCommand => {
            std.debug.print("Error: Unknown command\n", .{});
            return err;
        },
        error.MissingArguments => {
            std.debug.print("Error: Missing arguments\n", .{});
            return err;
        },
        else => {
            std.debug.print("Error: {}\n", .{err});
            return err;
        },
    };

    std.process.exit(exit_code);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
