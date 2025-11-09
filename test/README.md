# ZIM Test Suite

Comprehensive testing infrastructure for ZIM with memory leak detection and performance benchmarking.

## Directory Structure

```
test/
├── unit/              # Unit tests with memory leak detection
│   ├── test_system_zig.zig
│   └── test_zls.zig
├── integration/       # Integration tests (future)
├── benchmarks/        # Performance benchmarks
│   ├── bench_system_zig.zig
│   ├── bench_zls.zig
│   └── run_benchmarks.sh
├── test_imports.zig   # Test helper module
├── run_tests.sh       # Test runner script
└── README.md          # This file
```

## Running Tests

### All Tests
```bash
zig build test-unit
```

### Memory Leak Detection
```bash
zig build memcheck
```

All tests use `std.testing.allocator` which automatically detects memory leaks. If any test leaks memory, it will fail with a clear error message.

### Individual Test Files
```bash
# Run specific test
zig test test/unit/test_system_zig.zig --main-mod-path .

# Run with verbose output
zig test test/unit/test_zls.zig --main-mod-path . --summary all
```

### Using Test Script
```bash
./test/run_tests.sh
```

## Running Benchmarks

### All Benchmarks
```bash
zig build bench
```

### Individual Benchmarks
```bash
./test/benchmarks/run_benchmarks.sh
```

Or run specific benchmarks:
```bash
zig build-exe test/benchmarks/bench_system_zig.zig \
    --main-mod-path . \
    -O ReleaseFast \
    -femit-bin=bench_system_zig

./bench_system_zig
```

## Test Coverage

### Unit Tests

#### SystemZig Tests (`test_system_zig.zig`)
- ✅ Instance creation and validation
- ✅ System Zig path detection
- ✅ Installation status checking
- ✅ Version extraction and parsing
- ✅ ZigInfo struct memory management
- ✅ Active Zig detection logic
- ✅ No memory leaks in typical workflow

#### ZLS Tests (`test_zls.zig`)
- ✅ ZlsManager initialization and cleanup
- ✅ System ZLS detection
- ✅ Installation status checking
- ✅ Version retrieval with error handling
- ✅ Configuration file generation
- ✅ Multiple init/deinit cycles
- ✅ No memory leaks in full workflow

### Benchmarks

#### SystemZig Benchmarks (`bench_system_zig.zig`)
- `init()` - Instance creation performance
- `isInstalled()` - Installation check speed
- `getPath()` - Path lookup performance
- `getVersion()` - Version extraction speed
- Memory usage analysis

#### ZLS Benchmarks (`bench_zls.zig`)
- `init()/deinit()` - Lifecycle performance
- `findSystemZls()` - System detection speed
- `isInstalled()` - Installation check performance
- `getVersion()` - Version retrieval speed
- `generateConfig()` - Config generation performance
- Memory usage analysis

## Memory Leak Detection

All tests automatically detect memory leaks using Zig's `std.testing.allocator`:

```zig
test "no memory leaks" {
    const allocator = testing.allocator;  // Leak-detecting allocator

    var sys_zig = system_zig.SystemZig.init(allocator);
    const version = try sys_zig.getVersion();
    if (version) |v| {
        defer allocator.free(v);  // Must free all allocations
    }

    // If any allocation is not freed, test fails
}
```

## Adding New Tests

### Unit Test Template

```zig
const std = @import("std");
const testing = std.testing;
const test_imports = @import("test_imports");
const my_module = test_imports.my_module;

test "descriptive test name" {
    const allocator = testing.allocator;

    // Your test code here
    // testing.allocator will detect leaks automatically
}
```

### Benchmark Template

```zig
const std = @import("std");
const test_imports = @import("test_imports");
const my_module = test_imports.my_module;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const iterations = 1000;
    var timer = try std.time.Timer.start();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Operation to benchmark
    }

    const elapsed = timer.read();
    const avg_ns = elapsed / iterations;
    std.debug.print("Operation: {d} ns/op\n", .{avg_ns});
}
```

## CI/CD Integration

While ZIM doesn't use automated CI/CD, these tests are designed to be run locally:

```bash
# Pre-commit checks
zig build test-unit          # Run all unit tests
zig build memcheck           # Memory leak detection
zig build bench              # Performance regression checks

# Comprehensive check
./test/run_tests.sh && zig build bench
```

## Test Guidelines

1. **Always use `testing.allocator`** for leak detection
2. **Clean up all resources** with `defer`
3. **Test error paths** as well as success paths
4. **Keep tests focused** - one concept per test
5. **Document expected behavior** with comments
6. **Use descriptive test names** - explain what's being tested

## Troubleshooting

### Test Failures

If a test fails:
1. Check error message for specific failure
2. Run test in isolation: `zig test test/unit/test_file.zig --main-mod-path .`
3. Use `--summary all` for detailed output
4. Check if memory leak detected (will show allocation trace)

### Memory Leak Debugging

If you see a memory leak:
```
error: memory leak detected
[gpa] (err): memory address 0x12345... leaked:
/path/to/file.zig:42:33: 0x... in function (...)
```

The stack trace shows where the allocation occurred. Add the corresponding `defer allocator.free(...)`.

## Performance Baselines

Typical benchmark results (for reference):

```
SystemZig.init:          50-100 ns/op
SystemZig.isInstalled:   5000-10000 ns/op (file system checks)
SystemZig.getVersion:    5-10 ms/op (spawns process)

ZlsManager.init+deinit:  200-500 ns/op
ZlsManager.findSystemZls: 5000-10000 ns/op
```

Significant deviations may indicate performance regressions.

## See Also

- [Main README](../README.md)
- [CLI Documentation](../docs/CLI.md)
- [Configuration Guide](../docs/CONFIGURATION.md)
