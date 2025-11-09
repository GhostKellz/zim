# ZIM Configuration Guide

Complete guide to configuring ZIM - Zig Infrastructure Manager.

## Table of Contents

- [Configuration Files](#configuration-files)
- [Global Configuration](#global-configuration)
- [Project Configuration](#project-configuration)
- [Environment Variables](#environment-variables)
- [Configuration Precedence](#configuration-precedence)
- [Examples](#examples)

---

## Configuration Files

ZIM uses TOML configuration files at multiple levels:

| File | Location | Purpose |
|------|----------|---------|
| `config.toml` | `~/.config/zim/` | Global ZIM settings |
| `toolchain.toml` | `.zim/` (project root) | Project-specific Zig version |
| `zim.toml` | Project root | Dependency manifest |
| `zim.lock` | Project root | Lockfile (auto-generated) |

---

## Global Configuration

**Location:** `~/.config/zim/config.toml`

This file controls global ZIM behavior across all projects.

### Full Example

```toml
[cache]
# Cache directory for dependencies
dir = "/home/user/.cache/zim"

# Maximum cache size in bytes (10GB)
max_size = 10737418240

# Clean cache older than N days
max_age_days = 90

[toolchains]
# Directory for Zig installations
dir = "/home/user/.zim/toolchains"

# Default Zig version for new projects
default_version = "0.16.0"

[targets]
# Directory for cross-compilation targets
dir = "/home/user/.zim/targets"

[registry]
# Package registry URL (future feature)
url = "https://registry.zim.dev"

# Registry mirror for faster downloads
mirror = "https://mirror.example.com"

# Enable registry caching
cache_enabled = true

[policy]
# Require package signatures (future feature)
require_signatures = false

# Minimum signature level: "none", "basic", "sigstore"
min_signature_level = "none"

# Allowed dependency sources
allowed_sources = ["github.com", "gitlab.com", "bitbucket.org"]

# Denied dependency sources
denied_sources = []

# Require HTTPS for all downloads
require_https = true

[network]
# Custom CA bundle for HTTPS verification
ca_bundle = "/etc/ssl/certs/ca-bundle.crt"

# HTTP timeout in seconds
timeout = 300

# Maximum retry attempts
max_retries = 3

# Retry delay in seconds
retry_delay = 5

# Enable parallel downloads
parallel_downloads = true

# Maximum concurrent downloads
max_concurrent = 4

[build]
# Default optimization mode: "Debug", "ReleaseSafe", "ReleaseSmall", "ReleaseFast"
default_optimize = "Debug"

# Default target (leave empty for native)
default_target = ""

# Enable verbose build output
verbose = false

[logging]
# Log level: "debug", "info", "warn", "error"
level = "info"

# Log file location
file = "/home/user/.zim/logs/zim.log"

# Enable colored output
colors = true
```

### Cache Configuration

```toml
[cache]
dir = "/custom/cache/dir"
max_size = 10737418240  # 10GB in bytes
max_age_days = 90
```

**Options:**
- `dir`: Where to store cached dependencies
- `max_size`: Maximum cache size in bytes
- `max_age_days`: Clean cache entries older than this

### Registry Configuration

```toml
[registry]
url = "https://registry.zim.dev"
mirror = "https://mirror.example.com"
cache_enabled = true
```

**Options:**
- `url`: Primary package registry URL
- `mirror`: Mirror URL for fallback/faster downloads
- `cache_enabled`: Enable registry response caching

### Policy Configuration

```toml
[policy]
require_signatures = true
min_signature_level = "sigstore"
allowed_sources = ["github.com", "gitlab.com"]
denied_sources = ["malicious.com"]
require_https = true
```

**Options:**
- `require_signatures`: Require cryptographic signatures on packages
- `min_signature_level`: Minimum signature verification level
- `allowed_sources`: Whitelist of allowed dependency sources
- `denied_sources`: Blacklist of forbidden sources
- `require_https`: Reject non-HTTPS downloads

### Network Configuration

```toml
[network]
ca_bundle = "/etc/ssl/certs/ca-bundle.crt"
timeout = 300
max_retries = 3
retry_delay = 5
parallel_downloads = true
max_concurrent = 4
```

**Options:**
- `ca_bundle`: Custom CA certificate bundle for TLS
- `timeout`: HTTP request timeout in seconds
- `max_retries`: Number of retry attempts for failed downloads
- `retry_delay`: Delay between retries in seconds
- `parallel_downloads`: Enable parallel dependency downloads
- `max_concurrent`: Maximum number of concurrent downloads

---

## Project Configuration

### Toolchain Configuration

**Location:** `.zim/toolchain.toml`

Pin your project to a specific Zig version.

```toml
# ZIM toolchain configuration
zig = "0.16.0"

# Cross-compilation targets
targets = ["x86_64-linux-gnu", "wasm32-wasi", "aarch64-macos"]
```

**Created by:**
```bash
zim toolchain pin 0.16.0
```

### Dependency Manifest

**Location:** `zim.toml`

Define project metadata and dependencies.

```toml
[project]
name = "my-awesome-project"
version = "1.0.0"
zig = "0.16.0"
authors = ["Your Name <your.email@example.com>"]
license = "MIT"
description = "A fantastic Zig project"

[dependencies]
# Git dependency with branch
zsync = { git = "https://github.com/ghostkellz/zsync", ref = "main" }

# Git dependency with tag
zhttp = { git = "https://github.com/ghostkellz/zhttp", ref = "v0.1.4" }

# Git dependency with commit hash
zlog = { git = "https://github.com/ghostkellz/zlog", ref = "abc123def456" }

# Tarball dependency
zpack = {
    tarball = "https://example.com/zpack-1.0.0.tar.gz",
    hash = "sha256:abcdef1234567890..."
}

# Local dependency
mylib = { path = "../mylib" }

# Registry dependency (future)
# awesome-pkg = "^1.2.3"

[dev-dependencies]
# Dependencies only used for development/testing
test-framework = { git = "https://github.com/user/test", ref = "v1.0.0" }
benchmark-tool = { git = "https://github.com/user/bench", ref = "main" }

[targets]
# Default build targets
default = ["native", "wasm32-wasi"]

# Additional targets for CI/releases
release = ["x86_64-linux-gnu", "aarch64-linux-gnu", "x86_64-windows-gnu"]

[build]
# Build-specific configuration
optimize = "ReleaseSafe"
strip = false

[policy]
# Project-specific policy overrides
allowed_licenses = ["MIT", "Apache-2.0", "BSD-3-Clause"]
deny_git_protocols = ["git://"]
```

**Created by:**
```bash
zim deps init my-awesome-project
```

### Lockfile

**Location:** `zim.lock`

Auto-generated file containing resolved dependency versions and hashes.

```toml
# ZIM dependency lockfile
# This file is automatically generated. Do not edit manually.

[[dependency]]
name = "zsync"
version = "0.7.1"
source = "git+https://github.com/ghostkellz/zsync"
commit = "abc123def456789..."
hash = "sha256:1234567890abcdef..."
dependencies = ["zlog"]

[[dependency]]
name = "zlog"
version = "0.1.0"
source = "git+https://github.com/ghostkellz/zlog"
commit = "def456abc123..."
hash = "sha256:abcdef1234567890..."
dependencies = []

[[dependency]]
name = "zhttp"
version = "0.1.4"
source = "git+https://github.com/ghostkellz/zhttp"
commit = "789abc123def..."
hash = "sha256:567890abcdef1234..."
dependencies = ["zsync"]
```

**Generated by:**
```bash
zim deps fetch
```

---

## Environment Variables

ZIM respects the following environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `ZIM_CACHE_DIR` | Override cache directory | `~/.cache/zim` |
| `ZIM_TOOLCHAIN_DIR` | Override toolchain directory | `~/.zim/toolchains` |
| `ZIM_TARGETS_DIR` | Override targets directory | `~/.zim/targets` |
| `ZIM_CONFIG_FILE` | Custom config file path | `~/.config/zim/config.toml` |
| `ZIM_CA_BUNDLE` | Custom CA bundle for TLS | System default |
| `ZIM_REGISTRY_URL` | Custom registry URL | None |
| `ZIM_REQUIRE_SIGNATURES` | Require package signatures | `false` |
| `ZIM_LOG_LEVEL` | Logging level | `info` |
| `SSL_CERT_FILE` | Fallback CA bundle path | System default |

### Examples

```bash
# Use custom cache directory
export ZIM_CACHE_DIR=/tmp/zim-cache
zim deps fetch

# Use custom CA bundle
export ZIM_CA_BUNDLE=/path/to/custom-ca-bundle.crt
zim install 0.16.0

# Enable debug logging
export ZIM_LOG_LEVEL=debug
zim deps graph

# Require signatures
export ZIM_REQUIRE_SIGNATURES=true
zim verify
```

---

## Configuration Precedence

ZIM uses the following precedence order (highest to lowest):

1. **Command-line flags** — `--cache-dir`, `--config`, etc.
2. **Environment variables** — `ZIM_CACHE_DIR`, etc.
3. **Project configuration** — `.zim/toolchain.toml`, `zim.toml`
4. **Global configuration** — `~/.config/zim/config.toml`
5. **Built-in defaults**

### Example

If you have:
- Global config: `cache.dir = "/home/user/.cache/zim"`
- Environment: `ZIM_CACHE_DIR=/tmp/zim-cache`
- CLI flag: `--cache-dir /custom/cache`

ZIM will use: `/custom/cache` (CLI flag has highest precedence)

---

## Examples

### Corporate Environment with Custom CA

```toml
# ~/.config/zim/config.toml

[network]
ca_bundle = "/etc/pki/tls/certs/ca-bundle.crt"
require_https = true

[policy]
allowed_sources = ["internal-gitlab.company.com", "github.com"]
require_signatures = true
```

### Offline Development Setup

```toml
# ~/.config/zim/config.toml

[registry]
url = "https://registry.company.com"
mirror = "file:///mnt/registry-mirror"
cache_enabled = true

[cache]
max_size = 53687091200  # 50GB for large teams
max_age_days = 365      # Keep for 1 year
```

### CI/CD Configuration

```toml
# ~/.config/zim/config.toml

[cache]
dir = "/ci/cache/zim"
max_size = 5368709120  # 5GB

[network]
parallel_downloads = true
max_concurrent = 8
timeout = 600

[build]
default_optimize = "ReleaseSafe"
verbose = true
```

### Security-Focused Setup

```toml
# ~/.config/zim/config.toml

[policy]
require_signatures = true
min_signature_level = "sigstore"
allowed_sources = ["github.com"]
denied_sources = []
require_https = true

[network]
max_retries = 0  # Fail fast, don't retry
```

### Development Workstation

```toml
# ~/.config/zim/config.toml

[toolchains]
default_version = "0.16.0"

[cache]
dir = "/fast/ssd/zim-cache"
max_size = 21474836480  # 20GB

[network]
parallel_downloads = true
max_concurrent = 6

[logging]
level = "info"
colors = true
```

---

## Configuration Tips

### Performance Optimization

1. **Use SSD for cache:** Set `cache.dir` to SSD location
2. **Enable parallel downloads:** Set `network.parallel_downloads = true`
3. **Increase cache size:** Set `cache.max_size` appropriately
4. **Use local mirror:** Configure `registry.mirror` for faster access

### Security Hardening

1. **Enable signature verification:** `policy.require_signatures = true`
2. **Whitelist sources:** Set `policy.allowed_sources`
3. **Require HTTPS:** `policy.require_https = true`
4. **Use custom CA bundle:** Configure `network.ca_bundle`

### Debugging

1. **Enable verbose logging:** `logging.level = "debug"`
2. **Enable verbose builds:** `build.verbose = true`
3. **Check configuration:** `zim doctor`

---

## Troubleshooting

### Cache Issues

If you're experiencing cache corruption:

```bash
# Check cache health
zim cache doctor

# Prune corrupted entries
zim cache prune

# Or completely clear cache
rm -rf ~/.cache/zim
```

### TLS/Certificate Issues

If you get TLS errors:

```bash
# Use custom CA bundle
export ZIM_CA_BUNDLE=/path/to/ca-bundle.crt
zim install 0.16.0

# Or configure globally in config.toml
```

### Configuration Not Loaded

Check configuration is valid TOML:

```bash
# Validate TOML syntax
zim doctor

# Check which config is being used
zim --verbose doctor
```

---

## See Also

- [CLI Documentation](CLI.md)
- [API Documentation](API.md)
- [README](../README.md)
