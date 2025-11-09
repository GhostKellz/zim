const std = @import("std");
const zhttp = @import("zhttp");
const zcrypto = @import("zcrypto");

/// Download a file from a URL and save to disk using zhttp
pub fn downloadFile(
    allocator: std.mem.Allocator,
    url: []const u8,
    output_path: []const u8,
) !void {
    std.debug.print("Downloading: {s}\n", .{url});

    // Use zhttp.download for simple file downloads
    try zhttp.download(allocator, url, output_path);

    std.debug.print("✓ Downloaded successfully\n", .{});
}

/// Download and verify hash using zcrypto
pub fn downloadFileVerified(
    allocator: std.mem.Allocator,
    url: []const u8,
    output_path: []const u8,
    expected_hash: []const u8,
) !void {
    try downloadFile(allocator, url, output_path);

    // Verify hash using zcrypto
    const actual_hash = try computeFileSha256(allocator, output_path);
    defer allocator.free(actual_hash);

    if (!std.mem.eql(u8, expected_hash, actual_hash)) {
        std.debug.print("Hash mismatch!\n", .{});
        std.debug.print("  Expected: {s}\n", .{expected_hash});
        std.debug.print("  Actual:   {s}\n", .{actual_hash});
        // Delete the corrupted file
        std.fs.deleteFileAbsolute(output_path) catch {};
        return error.HashMismatch;
    }

    std.debug.print("✓ Hash verified\n", .{});
}

/// Extract a tar.xz archive using std.tar and std.compress.xz
pub fn extractTarXz(
    allocator: std.mem.Allocator,
    archive_path: []const u8,
    output_dir: []const u8,
) !void {
    std.debug.print("Extracting: {s}\n", .{archive_path});
    std.debug.print("To: {s}\n", .{output_dir});

    // Open the .tar.xz file
    const file = try std.fs.openFileAbsolute(archive_path, .{});
    defer file.close();

    // For now, shell out to tar since std.compress.xz isn't fully available yet
    // TODO: Use std.compress.xz when it's stable in Zig 0.16
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "tar",
            "-xJf",
            archive_path,
            "-C",
            output_dir,
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        std.debug.print("tar failed: {s}\n", .{result.stderr});
        return error.ExtractionFailed;
    }

    std.debug.print("✓ Extracted successfully\n", .{});
}

/// Compute SHA256 hash of a file using zcrypto
pub fn computeFileSha256(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) ![]const u8 {
    const file = try std.fs.openFileAbsolute(file_path, .{});
    defer file.close();

    // Use zcrypto's streaming hasher
    var hasher = zcrypto.hash.Sha256.init();
    var buf: [8192]u8 = undefined;

    while (true) {
        const bytes_read = try file.read(&buf);
        if (bytes_read == 0) break;
        hasher.update(buf[0..bytes_read]);
    }

    const digest = hasher.final();

    // Convert to hex string
    const hex_chars = "0123456789abcdef";
    var hex_buf: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        hex_buf[i * 2] = hex_chars[byte >> 4];
        hex_buf[i * 2 + 1] = hex_chars[byte & 0x0F];
    }

    return allocator.dupe(u8, &hex_buf);
}

test "download utils" {
    // Placeholder test
    const allocator = std.testing.allocator;
    _ = allocator;
}
