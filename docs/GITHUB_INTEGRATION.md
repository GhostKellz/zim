# GitHub Integration

ZIM provides first-class support for GitHub repositories with a convenient shorthand syntax.

## Shorthand Syntax

Instead of typing full Git URLs, use the GitHub shorthand:

```bash
gh/owner/repo[@ref]
```

### Examples

```bash
# Latest from default branch
zim deps add zig gh/ziglang/zig

# Specific tag/version
zim deps add zpack gh/hendriknielaender/zpack@v0.3.3

# Specific branch
zim deps add zsync gh/ghostkellz/zsync@main

# Specific commit
zim deps add mylib gh/user/mylib@abc1234
```

## How It Works

The shorthand is automatically expanded to:

```bash
gh/owner/repo@ref  →  https://github.com/owner/repo.git
```

For tarball downloads (recommended for releases):
```bash
gh/owner/repo@v1.0.0  →  https://github.com/owner/repo/archive/refs/tags/v1.0.0.tar.gz
```

## In zim.toml

You can use GitHub shorthand directly in your manifest:

```toml
[dependencies]
zpack = "gh/hendriknielaender/zpack@v0.3.3"
zsync = "gh/ghostkellz/zsync@main"
zig = "gh/ziglang/zig@0.11.0"
```

## API Integration

ZIM can fetch repository information from the GitHub API:

```bash
# Get latest release
zim deps add mylib gh/user/mylib@latest

# Show repo info
zim deps info gh/user/mylib
```

**Output:**
```
mylib
  A cool Zig library
  Default branch: main
  ⭐ 1234 stars
```

## Benefits

1. **Shorter syntax** - No need to type full URLs
2. **Auto-completion ready** - Easy to remember format
3. **Version-aware** - Explicit version tagging
4. **API integration** - Fetch metadata and latest releases
5. **Tarball optimization** - Uses release archives when available

## Comparison

**Before:**
```bash
zim deps add zpack --git https://github.com/hendriknielaender/zpack.git --ref v0.3.3
```

**After:**
```bash
zim deps add zpack gh/hendriknielaender/zpack@v0.3.3
```

## Advanced Usage

### Latest Release

```bash
# Automatically fetch latest release tag
zim deps add mylib gh/user/mylib@latest
```

### Private Repositories

For private repos, use SSH or configure Git credentials:

```bash
# SSH (if you have keys set up)
git config --global url."git@github.com:".insteadOf "https://github.com/"

# Then use normally
zim deps add private-repo gh/company/private-repo@main
```

### Monorepos

For packages within monorepos:

```toml
[dependencies]
# Point to subdirectory in post-fetch
mylib = { github = "gh/user/monorepo@main", path = "packages/mylib" }
```

## Error Handling

If a GitHub shorthand fails, ZIM provides clear error messages:

```
Error: Failed to resolve gh/user/nonexistent@main
  Repository not found or inaccessible

  Possible causes:
  - Repository doesn't exist
  - Repository is private (configure authentication)
  - Network connectivity issues

  Run 'zim doctor' to check system health
```

## See Also

- [Dependency Management](DEPENDENCIES.md)
- [Configuration Guide](CONFIGURATION.md)
- [CLI Reference](CLI.md)
