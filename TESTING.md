# ZIM Testing & Quality Assurance

Comprehensive testing infrastructure with automatic memory leak detection and performance benchmarking.

## Quick Start

```bash
# Run all unit tests with memory leak detection
zig build test-unit

# Run memory leak detection specifically
zig build memcheck

# Run performance benchmarks
zig build bench

# Run everything
zig build test-unit && zig build bench
```

## Test Infrastructure

### 🧪 Unit Tests

All unit tests use `std.testing.allocator` which **automatically detects memory leaks**. If any memory is not freed, the test fails immediately with a stack trace showing where the allocation occurred.

**Test Files:**
- `test/unit/test_system_zig.zig` - System Zig detection tests (8 tests)
- `test/unit/test_zls.zig` - ZLS manager tests (7 tests)

**Coverage:**
- ✅ Instance creation and lifecycle management
- ✅ System installation detection
- ✅ Version extraction and parsing
- ✅ Error handling and edge cases
- ✅ Memory management and cleanup
- ✅ Multiple init/deinit cycles

### ⚡ Benchmarks

Performance benchmarks to detect regressions and track optimization gains.

**Benchmark Files:**
- `test/benchmarks/bench_system_zig.zig` - SystemZig performance
- `test/benchmarks/bench_zls.zig` - ZLS manager performance

**Metrics Tracked:**
- Operation latency (nanoseconds per operation)
- Memory usage (bytes per struct/allocation)
- Iteration counts for statistical significance

### 📊 Test Results

**Latest Results** (on Linux x86_64):

```
Unit Tests:
✅ 8/8 SystemZig tests passed - NO MEMORY LEAKS
✅ 7/7 ZLS tests passed - NO MEMORY LEAKS

Benchmarks:
SystemZig.init:           0 ns/op (instantaneous)
SystemZig.isInstalled:    2.6 µs/op
SystemZig.getPath:        3.5 µs/op
SystemZig.getVersion:     2.4 ms/op (spawns process)

ZlsManager.init+deinit:   10 µs/op
ZlsManager.findSystemZls: 2.3 µs/op
ZlsManager.isInstalled:   2.3 µs/op
ZlsManager.getVersion:    250 µs/op

Memory Usage:
SystemZig struct:         16 bytes
ZigInfo struct:           56 bytes
ZlsManager struct:        (varies with string lengths)
```

## Memory Leak Detection

### How It Works

Zig's `std.testing.allocator` wraps all allocations and tracks them. When a test completes, it verifies that every allocation has been freed. If not, it provides:

1. **Memory address** that leaked
2. **Stack trace** showing where it was allocated
3. **Size** of the leaked allocation

### Example

```zig
test "memory leak detection" {
    const allocator = testing.allocator;  // Leak-detecting allocator

    const data = try allocator.alloc(u8, 100);
    // Forgot to free! Test will fail:
    // error: memory leak detected
    // [gpa] (err): memory address 0x... leaked:
    // test_file.zig:42:33: 0x... in function
}
```

**Correct Version:**
```zig
test "no memory leaks" {
    const allocator = testing.allocator;

    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);  // ✅ Properly freed

    // Test passes!
}
```

### Common Patterns

**Pattern 1: Simple Allocation**
```zig
const version = try allocator.dupe(u8, "0.16.0");
defer allocator.free(version);
```

**Pattern 2: Conditional Allocation**
```zig
const version = try getVersion();  // Returns ?[]const u8
if (version) |v| {
    defer allocator.free(v);
    // Use v...
}
```

**Pattern 3: Struct with Cleanup**
```zig
var mgr = try ZlsManager.init(allocator, dir1, dir2);
defer mgr.deinit();  // Frees internal allocations
```

**Pattern 4: Error Handling**
```zig
var list: std.ArrayList(u8) = .{};
errdefer list.deinit(allocator);  // Clean up on error

try list.appendSlice(allocator, data);
return list.toOwnedSlice(allocator);  // Transfer ownership
```

## Running Tests

### Via Build System

```bash
# All unit tests
zig build test-unit

# Memory leak detection (same as test-unit)
zig build memcheck

# All benchmarks
zig build bench

# Standard Zig tests (main + exe tests)
zig build test
```

### Via Test Scripts

```bash
# Comprehensive test runner
./test/run_tests.sh

# Benchmark runner
./test/benchmarks/run_benchmarks.sh
```

### Individual Tests

```bash
# Run single test file
zig test test/unit/test_system_zig.zig --main-mod-path .

# With verbose output
zig test test/unit/test_zls.zig --main-mod-path . --summary all

# With leak detection details
zig test test/unit/test_system_zig.zig --main-mod-path . -Dlog-level=debug
```

## Adding New Tests

### Unit Test Template

Create a new file in `test/unit/test_*.zig`:

```zig
const std = @import("std");
const testing = std.testing;
const test_imports = @import("test_imports");

// Import your module
const my_module = test_imports.my_module;

test "descriptive name of what you're testing" {
    const allocator = testing.allocator;  // ALWAYS use testing.allocator

    // Test code here
    var instance = try my_module.init(allocator);
    defer instance.deinit();  // Clean up

    // Assertions
    try testing.expect(instance.field == expected_value);
}
```

### Benchmark Template

Create a new file in `test/benchmarks/bench_*.zig`:

```zig
const std = @import("std");
const test_imports = @import("test_imports");
const my_module = test_imports.my_module;

const ITERATIONS = 1000;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 My Module Benchmarks\n", .{});
    std.debug.print("========================\n\n", .{});

    // Benchmark: operation
    {
        var timer = try std.time.Timer.start();
        var i: usize = 0;
        while (i < ITERATIONS) : (i += 1) {
            // Operation to benchmark
        }
        const elapsed = timer.read();
        const avg_ns = elapsed / ITERATIONS;
        std.debug.print("Operation: {d:>8} ns/op ({d} iterations)\n", .{ avg_ns, ITERATIONS });
    }

    std.debug.print("\n✅ Benchmarks complete\n\n", .{});
}
```

Then add to `build.zig`:

```zig
// In the test section
const my_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("test/unit/test_my_module.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "test_imports", .module = test_imports },
        },
    }),
});
const run_my_tests = b.addRunArtifact(my_tests);
unit_test_step.dependOn(&run_my_tests.step);
test_step.dependOn(&run_my_tests.step);
```

## Best Practices

### ✅ DO

1. **Always use `testing.allocator`** in tests
2. **Clean up with `defer`** immediately after allocation
3. **Test error paths** not just success cases
4. **Keep tests focused** - one concept per test
5. **Use descriptive names** - explain what's being tested
6. **Document edge cases** with comments
7. **Run tests before committing** to catch leaks early

### ❌ DON'T

1. **Don't use GPA in tests** - use `testing.allocator`
2. **Don't forget `defer`** cleanup
3. **Don't test too many things** in one test
4. **Don't skip error handling** tests
5. **Don't ignore benchmark regressions**

## Troubleshooting

### Memory Leak Detected

```
error: memory leak detected
[gpa] (err): memory address 0x7f1234567890 leaked:
/data/projects/zim/src/module.zig:42:33: 0x... in function
```

**Fix:** Add `defer allocator.free(...)` after the allocation on line 42.

### Test Fails Unexpectedly

1. Run in isolation: `zig test test/unit/test_file.zig --main-mod-path .`
2. Check for system dependencies (e.g., requires system Zig/ZLS)
3. Verify test assumptions (file paths, permissions, etc.)
4. Use `--summary all` for detailed output

### Benchmark Variance

Benchmarks may vary due to:
- System load
- CPU frequency scaling
- Background processes
- Disk I/O for file operations

Run multiple times and look for consistent patterns.

## CI/CD (Local)

While ZIM doesn't use automated CI/CD, run these locally before committing:

```bash
#!/bin/bash
# pre-commit.sh

set -e

echo "Running tests..."
zig build test-unit

echo "Running benchmarks..."
zig build bench

echo "Building ZIM..."
zig build

echo "✅ All checks passed!"
```

Make executable: `chmod +x pre-commit.sh`

## Performance Baselines

Use these as reference for detecting regressions:

| Operation | Expected | Notes |
|-----------|----------|-------|
| SystemZig.init | <100 ns | Struct initialization |
| SystemZig.isInstalled | 2-10 µs | File system checks |
| SystemZig.getVersion | 2-5 ms | Spawns subprocess |
| ZlsManager.init | 5-15 µs | String allocations |
| ZlsManager.findSystemZls | 2-10 µs | File system checks |

Significant deviations indicate potential performance issues.

## Future Enhancements

- [ ] Integration tests for end-to-end workflows
- [ ] Fuzzing tests for input validation
- [ ] Code coverage reporting
- [ ] Performance regression tracking
- [ ] Automated test report generation

## See Also

- [Test Directory README](test/README.md) - Detailed test documentation
- [Main README](README.md) - Project overview
- [CLI Documentation](docs/CLI.md) - Command-line interface
- [Configuration Guide](docs/CONFIGURATION.md) - Configuration options
