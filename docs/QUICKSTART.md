# ZIM Quick Start Guide

Welcome to **ZIM** (Zig Infrastructure Manager) - the unified toolchain, package, and runtime manager for Zig!

## Installation

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zim.git
cd zim

# Build ZIM
zig build

# Install to your PATH (optional)
sudo cp zig-out/bin/zim /usr/local/bin/
```

## Basic Usage

### Managing Toolchains

```bash
# Install a Zig version
zim install 0.16.0

# Or use the longer form
zim toolchain install 0.16.0

# Switch global Zig version
zim use 0.16.0

# Pin project to specific version
zim toolchain pin 0.16.0

# List installed toolchains
zim toolchain list
```

### Managing Targets

```bash
# Add cross-compilation targets
zim target add wasm32-wasi
zim target add aarch64-linux-gnu
zim target add x86_64-windows-gnu

# List available targets
zim target list

# Remove a target
zim target remove wasm32-wasi
```

### Managing Dependencies

```bash
# Initialize dependency manifest
zim deps init

# Add dependencies
zim deps add /data/projects/zsync              # Local path
zim deps add https://github.com/user/pkg.git   # Git URL
zim deps add https://example.com/pkg.tar.gz    # Tarball

# Fetch and cache dependencies
zim deps fetch

# Show dependency graph
zim deps graph
```

### Cache Management

```bash
# Show cache statistics
zim cache status

# Prune unused cache entries (dry run)
zim cache prune --dry-run

# Actually prune
zim cache prune

# Verify cache integrity
zim cache doctor
```

### Policy & Verification

```bash
# Audit dependencies against policy
zim policy audit

# Verify project integrity
zim verify

# With JSON output
zim verify --json
```

### System Diagnostics

```bash
# Run comprehensive diagnostics
zim doctor

# Check TLS/CA configuration, network, toolchains, etc.
```

### CI Integration

```bash
# Generate reproducible CI bootstrap configuration
zim ci bootstrap
```

## Project Configuration

Create `.zim/toolchain.toml` in your project root:

```toml
zig = "0.16.0"
targets = ["x86_64-linux-gnu", "wasm32-wasi"]

[cache]
max_size = "10GB"

[policy]
require_signatures = false
```

See `examples/toolchain.toml` for a complete example.

## Global Configuration

Create `~/.config/zim/config.toml`:

```toml
zig_version = "0.16.0"
toolchain_dir = "~/.zim/toolchains"

[cache]
dir = "~/.cache/zim"
max_size = "50GB"

[ghost]
local_projects_root = "/data/projects"
use_zsync = true
use_zontom = true
use_zhttp = true
```

See `examples/global-config.toml` for a complete example.

## Ghost Stack Integration

ZIM automatically detects and integrates with Ghost Stack libraries if they're available under `/data/projects/`:

- **zsync** - Async I/O for downloads
- **zontom** - TOML parsing for configs
- **zhttp** - HTTP client for fetches
- **phantom** - TUI mode (optional)
- **ghostlang** - Scripting mode (optional)

This gives you local-first development without needing to publish all libraries.

## Help & Documentation

```bash
# Show general help
zim help
zim --help

# Show version
zim version
zim --version

# Command-specific help
zim toolchain --help
zim deps --help
```

## Examples

```bash
# Complete workflow for a new project
zim install 0.16.0
zim use 0.16.0
cd my-project
zim toolchain pin 0.16.0
zim target add wasm32-wasi
zim deps init
zim deps add /data/projects/zsync
zim deps fetch
zim verify
```

## Next Steps

- Check out the [TODO.md](../TODO.md) to see what's planned
- Explore the [archive/babylon/](../archive/babylon/) for package manager inspiration
- Read about [Ghost Stack integration](../TODO.md#7-ghost-stack-integration-local)
- Learn about [MCP integration](../TODO.md#8-mcp--zion--editor-story) for AI assistants

---

**ZIM** - The missing link in the Zig toolchain.
