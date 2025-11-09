#!/usr/bin/env bash
set -euo pipefail

# ZIM Debian Package Builder
# This script builds a .deb package for ZIM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
PACKAGE_DIR="${BUILD_DIR}/zim_0.1.0-1_amd64"

echo "🔨 Building ZIM Debian package..."

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${PACKAGE_DIR}"

# Copy Debian control files
cp -r "${SCRIPT_DIR}/DEBIAN" "${PACKAGE_DIR}/"

# Create directory structure
mkdir -p "${PACKAGE_DIR}/usr/bin"
mkdir -p "${PACKAGE_DIR}/usr/share/doc/zim"
mkdir -p "${PACKAGE_DIR}/usr/share/licenses/zim"

# Build ZIM
echo "📦 Building ZIM binary..."
cd "${PROJECT_ROOT}"
zig build -Doptimize=ReleaseSafe

# Copy binary
echo "📋 Copying files..."
cp "${PROJECT_ROOT}/zig-out/bin/zim" "${PACKAGE_DIR}/usr/bin/zim"
chmod 755 "${PACKAGE_DIR}/usr/bin/zim"

# Copy documentation
cp "${PROJECT_ROOT}/README.md" "${PACKAGE_DIR}/usr/share/doc/zim/"
cp "${PROJECT_ROOT}/docs/CLI.md" "${PACKAGE_DIR}/usr/share/doc/zim/"
cp "${PROJECT_ROOT}/docs/API.md" "${PACKAGE_DIR}/usr/share/doc/zim/"

# Copy license
if [ -f "${PROJECT_ROOT}/LICENSE" ]; then
    cp "${PROJECT_ROOT}/LICENSE" "${PACKAGE_DIR}/usr/share/licenses/zim/"
fi

# Build the package
echo "📦 Building .deb package..."
cd "${BUILD_DIR}"
dpkg-deb --build "${PACKAGE_DIR}"

# Move to release directory
mv zim_0.1.0-1_amd64.deb "${SCRIPT_DIR}/"

echo "✅ Package built successfully: ${SCRIPT_DIR}/zim_0.1.0-1_amd64.deb"
echo ""
echo "Install with: sudo dpkg -i ${SCRIPT_DIR}/zim_0.1.0-1_amd64.deb"
echo "Or: sudo apt install -f  (to install dependencies)"

# Clean up
rm -rf "${BUILD_DIR}"
