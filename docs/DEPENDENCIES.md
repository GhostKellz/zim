# Dependency Management

Complete guide to managing dependencies with ZIM.

## Table of Contents

- [Quick Start](#quick-start)
- [Dependency Sources](#dependency-sources)
- [Semantic Versioning](#semantic-versioning)
- [Dependency Resolution](#dependency-resolution)
- [Lockfiles](#lockfiles)
- [Dependency Graph](#dependency-graph)
- [Advanced Features](#advanced-features)

---

## Quick Start

```bash
# Initialize project
zim deps init my-project

# Add dependencies
zim deps add zpack gh/hendriknielaender/zpack@v0.3.3
zim deps add zsync gh/ghostkellz/zsync@main

# Fetch all dependencies
zim deps fetch

# View dependency tree
zim deps graph
```

---

## Dependency Sources

ZIM supports multiple dependency sources:

### 1. GitHub Shorthand (Recommended)

```bash
zim deps add mylib gh/owner/repo@v1.0.0
```

**Benefits:**
- Shortest syntax
- Auto-completion friendly
- Version explicit

See [GitHub Integration](GITHUB_INTEGRATION.md) for details.

### 2. Git Repositories

```bash
zim deps add mylib --git https://github.com/user/mylib.git --ref main
```

**Supports:**
- Branches: `--ref main`, `--ref develop`
- Tags: `--ref v1.0.0`
- Commits: `--ref abc1234`

### 3. Tarballs

```bash
zim deps add mylib --tarball https://example.com/mylib-1.0.0.tar.gz --hash sha256:abc123...
```

**Hash verification:**
- Required for security
- SHA-256 checksums
- Automatic verification

### 4. Local Paths

```bash
zim deps add mylib --path ../mylib
```

**Use cases:**
- Development dependencies
- Monorepo packages
- Local testing

### 5. Registry (Future)

```bash
zim deps add mylib@1.0.0
```

*Coming in v0.2*

---

## Semantic Versioning

ZIM uses semantic versioning with npm-style constraints.

### Version Format

```
major.minor.patch[-prerelease][+build]
```

**Examples:**
- `1.0.0` - Release version
- `1.0.0-alpha.1` - Prerelease
- `1.0.0+build.123` - Build metadata

### Constraint Syntax

| Syntax | Meaning | Example | Matches |
|--------|---------|---------|---------|
| `*` | Any version | `*` | Any |
| `1.2.3` | Exact version | `1.2.3` | 1.2.3 only |
| `^1.2.3` | Compatible with | `^1.2.3` | ≥1.2.3 <2.0.0 |
| `~1.2.3` | Approximately | `~1.2.3` | ≥1.2.3 <1.3.0 |
| `>=1.2.3` | Greater or equal | `>=1.2.3` | ≥1.2.3 |
| `<2.0.0` | Less than | `<2.0.0` | <2.0.0 |
| `1.0.0...2.0.0` | Range | `1.0.0...2.0.0` | ≥1.0.0 ≤2.0.0 |

### Caret Ranges (`^`)

**Allows changes that don't modify the left-most non-zero digit:**

```
^1.2.3  →  ≥1.2.3 <2.0.0   (major locked)
^0.2.3  →  ≥0.2.3 <0.3.0   (minor locked)
^0.0.3  →  ≥0.0.3 <0.0.4   (patch locked)
```

**Use case:** Default for most dependencies

### Tilde Ranges (`~`)

**Allows patch-level changes:**

```
~1.2.3  →  ≥1.2.3 <1.3.0   (patch updates only)
~1.2    →  ≥1.2.0 <1.3.0   (same)
~1      →  ≥1.0.0 <2.0.0   (major locked)
```

**Use case:** Conservative updates

### In zim.toml

```toml
[dependencies]
# Exact version
mylib = "1.2.3"

# Caret (recommended)
zpack = "^0.3.3"

# Tilde
zsync = "~1.0.0"

# Range
zig = "0.11.0...0.16.0"

# Any version (not recommended)
testlib = "*"
```

---

## Dependency Resolution

ZIM automatically resolves dependency conflicts.

### Conflict Detection

```bash
# Detects version conflicts
zim deps fetch
```

**Example conflict:**
```
Error: Dependency conflict detected

  Package: zpack
    Required by project: ^0.3.0
    Required by zsync:   ^0.2.0

  No version satisfies both constraints

  Suggestions:
    - Update zsync to version that supports zpack ^0.3.0
    - Downgrade project requirement to zpack ^0.2.0
```

### Transitive Dependencies

ZIM automatically resolves transitive (indirect) dependencies:

```
my-project
├── zpack ^0.3.3
│   └── miniz (transitive)
└── zsync ^1.0.0
    ├── zpack ^0.3.0 (conflict resolution)
    └── flash ^0.1.0 (transitive)
```

### Circular Dependency Detection

```bash
zim deps graph
```

**Detects cycles:**
```
📦 Dependency Graph
─────────────────────

my-project @ 1.0.0
├─ lib-a @ 1.0.0
│  └─ lib-b @ 1.0.0
│     └─ lib-a @ 1.0.0 ↻ (circular dependency detected!)

⚠ Warning: Circular dependency detected
  lib-a → lib-b → lib-a
```

---

## Lockfiles

ZIM uses `zim.lock` for reproducible builds.

### Generation

```bash
# Generate lockfile
zim deps fetch
```

**Creates:** `zim.lock` with exact versions and hashes

### Format

```toml
# zim.lock - Auto-generated, do not edit manually

version = 1

[[package]]
name = "zpack"
version = "0.3.3"
source = "git+https://github.com/hendriknielaender/zpack.git#v0.3.3"
hash = "1220abc123..."

[[package]]
name = "zsync"
version = "1.0.0"
source = "git+https://github.com/ghostkellz/zsync.git#main"
hash = "1220def456..."
dependencies = ["zpack"]
```

### Provenance Tracking

Each locked dependency includes:
- **origin**: Source URL
- **digest**: SHA-256 hash
- **fetched_at**: ISO 8601 timestamp
- **size**: File size in bytes

**Example:**
```toml
[[package]]
name = "zpack"
version = "0.3.3"
source = "gh/hendriknielaender/zpack@v0.3.3"
hash = "1220abc123..."

[package.provenance]
origin = "https://github.com/hendriknielaender/zpack"
digest = "sha256:abc123..."
fetched_at = "2024-11-15T10:30:00Z"
size = 125847
```

### Lockfile Workflow

```bash
# 1. Edit zim.toml
vim zim.toml

# 2. Update lockfile
zim deps fetch

# 3. Check diff
git diff zim.lock

# 4. Commit both
git add zim.toml zim.lock
git commit -m "Update dependencies"
```

---

## Dependency Graph

### Visualization

```bash
zim deps graph
```

**Output:**
```
📦 Dependency Graph
─────────────────────

my-project @ 1.0.0
├─ zpack @ 0.3.3
│  ├─ miniz @ 3.0.2
│  └─ zlib @ 1.2.13
├─ zsync @ 1.0.0
│  ├─ zpack @ 0.3.3 ↻ (already shown)
│  └─ flash @ 0.1.0
└─ zhttp @ 0.2.0
   └─ zsync @ 1.0.0 ↻ (already shown)
```

**Symbols:**
- `├─` - Dependency branch
- `│` - Continuation
- `↻` - Already shown (prevents duplication)

### Graph Export

```bash
# Export to DOT format
zim deps graph --format dot > deps.dot

# Generate image with Graphviz
dot -Tpng deps.dot -o deps.png
```

---

## Advanced Features

### Policy Enforcement

Create `.zim/policy.json`:

```json
{
  "allow": ["github.com/*"],
  "deny": ["malicious/*"],
  "require_hash": true
}
```

```bash
# Audit dependencies
zim policy audit
```

See [Diagnostics](DIAGNOSTICS.md) for details.

### Workspace Support

For monorepos:

```toml
# workspace.toml
[workspace]
members = ["packages/*"]

[workspace.dependencies]
shared-dep = "^1.0.0"
```

```bash
# Fetch all workspace deps
zim deps fetch --workspace
```

### Offline Builds

```bash
# Populate cache
zim deps fetch

# Build offline
zim build --offline
```

### Dependency Updates

```bash
# Check for updates
zim deps outdated

# Update single dependency
zim deps update zpack

# Update all dependencies
zim deps update --all
```

### Pruning

```bash
# Remove unused dependencies
zim deps prune

# Clean cache
zim cache clean
```

---

## See Also

- [GitHub Integration](GITHUB_INTEGRATION.md)
- [Diagnostics](DIAGNOSTICS.md)
- [CLI Reference](CLI.md)
- [Configuration](CONFIGURATION.md)
