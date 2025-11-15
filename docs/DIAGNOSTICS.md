# ZIM Diagnostics & Health Checks

ZIM provides comprehensive diagnostic tools to ensure your development environment is healthy and properly configured.

## Table of Contents

- [System Diagnostics](#system-diagnostics)
- [Cache Integrity](#cache-integrity)
- [Workspace Diagnostics](#workspace-diagnostics)
- [Policy Audits](#policy-audits)

---

## System Diagnostics

### `zim doctor`

Runs a complete system health check.

```bash
zim doctor
```

**Output Example:**
```
🔍 ZIM System Diagnostics
─────────────────────────

  ✓ Zig Installation: Zig 0.16.0-dev.1225+bf9082518 installed
  ✓ Cache Directory: Cache directory exists: /home/user/.cache/zim
  ✓ Global Config: Global config loaded successfully
  ✓ Network Connectivity: Network connectivity is working
  ✓ Disk Space: Disk space available

─────────────────────────
✅ All checks passed (5 ok)
```

### Checks Performed

1. **Zig Installation**
   - Verifies `zig` is in PATH
   - Reports installed version
   - Checks if Zig command works

2. **Cache Directory**
   - Validates cache directory exists
   - Reports cache location
   - Checks write permissions

3. **Global Configuration**
   - Loads `~/.config/zim/config.toml`
   - Validates configuration syntax
   - Reports any issues

4. **Network Connectivity**
   - Tests connection to github.com
   - Verifies DNS resolution
   - Checks if downloads will work

5. **Disk Space**
   - Checks available space
   - Warns if running low
   - Reports cache partition usage

### Diagnostic Results

Each check returns one of:
- `✓` **OK** - Check passed
- `⚠` **Warning** - Non-critical issue
- `✗` **Error** - Critical problem

---

## Cache Integrity

### `zim cache integrity`

Verifies the integrity of the dependency cache.

```bash
zim cache integrity
```

**What it checks:**
- File readability
- Hash verification
- Corruption detection
- Orphaned files

**Output Example:**
```
🔍 Cache Integrity Check
────────────────────────

Scanning cache directory...

────────────────────────
  Total files: 42
  Total size: 125847291 bytes

✅ Cache integrity OK
```

**If corruption detected:**
```
🔍 Cache Integrity Check
────────────────────────

Scanning cache directory...

  ✗ Corrupted: ab/cd/abcdef123456...
  ✗ Corrupted: 12/34/123456789abc...

────────────────────────
  Total files: 42
  Total size: 125847291 bytes
  Corrupted files: 2

⚠ Run 'zim cache clean' to remove corrupted files
```

### Fixing Cache Issues

```bash
# Clean corrupted files
zim cache clean

# Rebuild cache
zim deps fetch --force
```

---

## Workspace Diagnostics

### `zim doctor workspace`

Checks for manifest/lockfile drift and synchronization issues.

```bash
zim doctor workspace
```

**Checks Performed:**

1. **Manifest Existence**
   - Verifies `zim.toml` exists
   - Reports if missing

2. **Lockfile Existence**
   - Verifies `zim.lock` exists
   - Suggests generation if missing

3. **Timestamp Comparison**
   - Compares `zim.toml` vs `zim.lock` modification times
   - Detects if manifest was edited after last fetch

4. **build.zig.zon Sync**
   - Checks if `build.zig.zon` is up-to-date
   - Suggests export if needed

**Output Examples:**

**✅ All in Sync:**
```
🔍 Workspace Diagnostics
────────────────────────

✓ Found zim.toml
✓ Found zim.lock

✅ Manifest and lockfile are in sync
✓ build.zig.zon is up to date
```

**⚠ Drift Detected:**
```
🔍 Workspace Diagnostics
────────────────────────

✓ Found zim.toml
✓ Found zim.lock

⚠ Manifest is newer than lockfile
  zim.toml has been modified since last fetch
  Run 'zim deps fetch' to update lockfile

⚠ Lockfile is newer than build.zig.zon
  Run 'zim deps export' to update build.zig.zon
```

**❌ Missing Files:**
```
🔍 Workspace Diagnostics
────────────────────────

✗ No zim.toml found in current directory
  Run 'zim init' to create a new project
```

### Fixing Workspace Issues

```bash
# Update lockfile after editing manifest
zim deps fetch

# Sync build.zig.zon with lockfile
zim deps export

# Start fresh project
zim init my-project
```

---

## Policy Audits

### `zim policy audit`

Validates dependencies against security policies.

```bash
zim policy audit
```

**Requires** a policy file at `.zim/policy.json`:

```json
{
  "allow": [
    "github.com/*",
    "ziglang.org/*"
  ],
  "deny": [
    "malicious/*",
    "untrusted/*"
  ],
  "require_hash": true
}
```

**Output Example:**

**✅ All Pass:**
```
📋 Policy Audit Report
─────────────────────

✓ All 8 dependencies passed policy checks
```

**⚠ Violations:**
```
📋 Policy Audit Report
─────────────────────

⚠ 2/8 dependencies failed policy checks

Violations:
  ✗ suspicious-package
    Package 'suspicious-package' matches deny pattern: untrusted/*

  ✗ no-hash-package
    Package 'no-hash-package' requires hash verification but none provided
```

### Policy Enforcement

ZIM can enforce policies at different strictness levels:

```toml
# .zim/config.toml
[policy]
mode = "strict"  # "strict", "warn", or "off"
```

- **strict**: Fail builds on policy violations
- **warn**: Show warnings but allow builds
- **off**: Disable policy checks

---

## Continuous Diagnostics

### In CI/CD

Run diagnostics as part of your CI pipeline:

```yaml
# .github/workflows/ci.yml
- name: ZIM Doctor
  run: |
    zim doctor
    zim doctor workspace
    zim cache integrity
    zim policy audit
```

### Pre-commit Hooks

Add diagnostics to pre-commit:

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Check workspace health
if ! zim doctor workspace; then
    echo "❌ Workspace diagnostics failed"
    echo "Run 'zim doctor workspace' to see issues"
    exit 1
fi

# Audit dependencies
if ! zim policy audit; then
    echo "❌ Policy audit failed"
    exit 1
fi
```

---

## Troubleshooting

### Common Issues

**1. "Zig not found in PATH"**
```bash
# Install Zig via ZIM
zim install 0.16.0
zim use 0.16.0

# Or add system Zig to PATH
export PATH="$PATH:/path/to/zig"
```

**2. "Cache directory permission denied"**
```bash
# Fix permissions
chmod -R u+w ~/.cache/zim

# Or use custom cache dir
zim --cache-dir /tmp/zim-cache deps fetch
```

**3. "Network connectivity issues"**
```bash
# Test connectivity
ping github.com

# Check proxy settings
echo $HTTP_PROXY
echo $HTTPS_PROXY

# Use custom CA bundle
zim --ca-bundle /etc/ssl/certs/ca-bundle.crt deps fetch
```

**4. "Manifest/lockfile out of sync"**
```bash
# Simple fix - refetch
zim deps fetch

# If that fails - clean and refetch
rm zim.lock
zim deps fetch
```

---

## Diagnostic Reports

Generate a full diagnostic report for bug reports:

```bash
# Generate report
zim doctor --json > zim-report.json

# Include in issue
cat zim-report.json
```

**Report includes:**
- ZIM version
- Zig version
- OS and architecture
- Cache status
- Configuration
- Network connectivity
- Recent errors

---

## See Also

- [Configuration Guide](CONFIGURATION.md)
- [CLI Reference](CLI.md)
- [Troubleshooting](TROUBLESHOOTING.md)
