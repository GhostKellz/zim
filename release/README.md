# ZIM Release Packages

This directory contains packaging configurations for various Linux distributions.

## Arch Linux

### Building the Package

```bash
cd release
makepkg -si
```

### Installing from AUR (Future)

```bash
yay -S zim
# or
paru -S zim
```

### Manual Installation

```bash
# Download PKGBUILD
curl -O https://raw.githubusercontent.com/ghostkellz/zim/main/release/PKGBUILD

# Build and install
makepkg -si
```

## Debian/Ubuntu

### Building the Package

```bash
cd release/debian
./build-deb.sh
```

### Installing the .deb Package

```bash
sudo dpkg -i zim_0.1.0-1_amd64.deb
sudo apt-get install -f  # Install dependencies if needed
```

## Fedora/RHEL

### Building the RPM (Coming Soon)

```bash
cd release/fedora
rpmbuild -ba zim.spec
```

## From Source

For all distributions, you can build from source:

```bash
git clone https://github.com/ghostkellz/zim.git
cd zim
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zim /usr/local/bin/
```

## Automated Installer

Use the automated installer script from the root directory:

```bash
curl -fsSL https://raw.githubusercontent.com/ghostkellz/zim/main/install.sh | bash
```

Or download and run manually:

```bash
wget https://raw.githubusercontent.com/ghostkellz/zim/main/install.sh
chmod +x install.sh
./install.sh
```

## Verifying Installation

After installation, verify ZIM is working:

```bash
zim --version
zim doctor
```

## Uninstallation

### Arch Linux

```bash
sudo pacman -R zim
```

### Debian/Ubuntu

```bash
sudo apt remove zim
```

### Manual Installation

```bash
sudo rm /usr/local/bin/zim
rm -rf ~/.zim
rm -rf ~/.cache/zim
```

## Package Maintainers

If you'd like to maintain ZIM packages for your distribution, please:

1. Open an issue at https://github.com/ghostkellz/zim/issues
2. Reference this repository's packaging files
3. Keep packages in sync with releases

We appreciate community packaging efforts!
