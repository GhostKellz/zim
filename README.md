<div align="center">
  <img src="assets/icons/zim.png" alt="ZIM Logo" width="200"/>
</div>

# ZIM — Zig Infrastructure Manager

ZIM is the **next-generation toolchain manager for the Zig ecosystem**, inspired by Rust’s `rustup` and Go’s `gvm`, but built natively in Zig. It seamlessly integrates with **Babylon** (package manager), **ZMake** (build orchestrator), **Veridion** (security/provenance), and **Apollo** (observability) to create a fully reproducible, policy-aware development environment.

---

## 🚀 Mission

> To make Zig toolchains **reproducible, portable, and secure by default** — one command away.

ZIM provides a unified interface for managing Zig versions, build targets, registries, and caches, while ensuring deterministic builds and strong provenance enforcement.

---

## ✨ Core Features

### 🔧 Toolchain Management

* Install, switch, and pin Zig versions per-project or globally.
* Auto-detect `.zim/toolchain.toml` and activate environments automatically.
* Verify signatures for official and custom Zig releases.

### 🎯 Target Management

* Install sysroots and stdlib targets for cross-compilation.
* Define reusable build profiles (e.g., `cross-linux`, `embedded`, `web`).
* Mirror toolchains and targets locally for offline builds.

### 🧱 Babylon Integration

* Use the correct Babylon registry and dependency graph for the active toolchain.
* Automatically lock Babylon versions to the current Zig release.
* Verify package integrity and signatures via Veridion.

### 🧮 Apollo Metrics & Cache

* Shared content-addressable cache for all Zig builds.
* Expose Prometheus metrics (cache hits, build time, downloads).
* Cache pruning, deduplication, and profile-aware LRU cleanup.

### 🔐 Veridion Provenance Enforcement

* Require signed toolchains, packages, and registry manifests.
* Validate checksums and issue attestation logs for CI/CD.
* Optional SBOM export and cosign support.

### 🧰 ZMake Integration

* Plug directly into ZMake for system-level packaging.
* Auto-hydrate toolchains in reproducible chroot environments.
* Unified TOML configuration and policy layers.

---

## 🧩 Directory Layout

```
zim/
├─ toolchains/        # Installed Zig releases and metadata
├─ targets/           # Cross-compile sysroots and stdlibs
├─ cache/             # CAS for build outputs and dependencies
├─ babylon-bridge/    # Registry + lockfile integration
├─ policy/            # Veridion signatures, SBOM, provenance
└─ telemetry/         # Apollo metrics exporter
```

---

## ⚡ Quick Start

```bash
# Install latest stable Zig
tim install latest

# Pin specific version in current project
tim toolchain pin 0.16.0

# Add cross targets
zim target add x86_64-linux-gnu aarch64-linux-gnu

# Sync Babylon dependencies
zim deps install

# Verify toolchain + provenance
zim verify --policy strict

# Cache stats & telemetry
zim cache status
```

---

## 🧱 Example: `.zim/toolchain.toml`

```toml
zig = "0.16.0"
targets = ["x86_64-linux-gnu", "aarch64-linux-gnu"]

[babylon]
registry = "https://registry.babylon.dev"
lockfile = "Babylon.lock"

[cache]
path = "~/.cache/zim"
max_size = "10GB"

[policy]
require_signatures = true
min_sig_level = "sigstore"
```

---

## 🔭 Roadmap

### Milestone 0.1 — Core Toolchains

* [x] Install/use/pin Zig versions
* [x] Detect `.zim/toolchain.toml`
* [ ] Add cross targets and cache layer

### Milestone 0.2 — Babylon & CI

* [ ] Integrate Babylon registry + lockfiles
* [ ] Add CI bootstrap commands
* [ ] Apollo metrics exporter

### Milestone 0.3 — Veridion + Policy

* [ ] Signature validation (toolchains, registries)
* [ ] SBOM and attestation exports
* [ ] Mirror + offline build support

### Milestone 0.4 — Profiles & Workspaces

* [ ] Multi-profile, multi-target builds
* [ ] Workspace awareness (monorepos)
* [ ] Policy-aware chroot provisioning for ZMake

---

## 🧠 Philosophy

* **Reproducibility First:** Every build is tied to a specific Zig version and registry state.
* **Transparency:** Signatures, hashes, and provenance are auditable and visible.
* **Composability:** Integrates with Babylon, ZMake, Veridion, and Apollo natively.
* **Performance:** Written in Zig, statically linked, and portable.

---

## 🛠️ Tech Stack

* **Language:** Zig 0.16.0+
* **Format:** TOML via ZonTOM parser
* **Security:** Sigstore / Veridion integration
* **Telemetry:** Apollo (Prometheus endpoint)

---

## 🧩 Example CLI Reference

```
zim toolchain install 0.16.0
zim toolchain use 0.16.0
zim toolchain pin 0.16.0
zim target add wasm32-wasi
zim deps verify
zim verify --policy strict
zim cache clean --older-than 30d
zim ci bootstrap
```

---

### Tagline

**ZIM — The missing link in the Zig toolchain.**

