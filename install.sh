#!/usr/bin/env bash
set -euo pipefail

# ZIM Installer Script
# Automated installation for multiple Linux distributions
# Colors inspired by Gemini CLI

# Color definitions - Big Blue, Teal, Minty Green, Regular Blue
BOLD='\033[1m'
RESET='\033[0m'
BIG_BLUE='\033[1;38;5;33m'      # Bright blue
TEAL='\033[1;38;5;51m'           # Cyan/Teal
MINTY_GREEN='\033[1;38;5;121m'   # Mint green
REGULAR_BLUE='\033[0;34m'        # Regular blue
RED='\033[1;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'

# Detect terminal width for centering
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)

# Function to center text
center_text() {
    local text="$1"
    local text_length=${#text}
    local padding=$(( (TERM_WIDTH - text_length) / 2 ))
    printf "%${padding}s%s\n" "" "$text"
}

# Function to print colored text
print_color() {
    local color="$1"
    local text="$2"
    echo -e "${color}${text}${RESET}"
}

# Function to print centered colored text
print_centered() {
    local color="$1"
    local text="$2"
    local padded_text=$(printf "%*s" $(( (${#text} + TERM_WIDTH) / 2 )) "$text")
    echo -e "${color}${padded_text}${RESET}"
}

# ASCII Art Logo
print_logo() {
    echo ""
    print_centered "${BIG_BLUE}" "╔══════════════════════════════════════════════════════════════╗"
    print_centered "${BIG_BLUE}" "║                                                              ║"
    print_centered "${TEAL}"     "║        ███████╗██╗███╗   ███╗                               ║"
    print_centered "${TEAL}"     "║        ╚══███╔╝██║████╗ ████║                               ║"
    print_centered "${MINTY_GREEN}" "║          ███╔╝ ██║██╔████╔██║                               ║"
    print_centered "${MINTY_GREEN}" "║         ███╔╝  ██║██║╚██╔╝██║                               ║"
    print_centered "${REGULAR_BLUE}" "║        ███████╗██║██║ ╚═╝ ██║                               ║"
    print_centered "${REGULAR_BLUE}" "║        ╚══════╝╚═╝╚═╝     ╚═╝                               ║"
    print_centered "${BIG_BLUE}" "║                                                              ║"
    print_centered "${TEAL}"     "║           Zig Infrastructure Manager                         ║"
    print_centered "${MINTY_GREEN}" "║        The all-in-one toolchain & package manager           ║"
    print_centered "${BIG_BLUE}" "║                                                              ║"
    print_centered "${BIG_BLUE}" "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# Detect distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_color "${RED}" "⚠️  Please do not run this script as root"
        print_color "${YELLOW}" "The script will ask for sudo password when needed"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    print_color "${TEAL}" "🔍 Checking dependencies..."

    for cmd in git curl tar xz zig; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_color "${RED}" "❌ Missing dependencies: ${missing_deps[*]}"
        print_color "${YELLOW}" "📦 Install them with:"

        case "$DISTRO" in
            arch|manjaro)
                echo "   sudo pacman -S ${missing_deps[*]}"
                ;;
            ubuntu|debian|pop)
                echo "   sudo apt install ${missing_deps[*]}"
                ;;
            fedora)
                echo "   sudo dnf install ${missing_deps[*]}"
                ;;
            *)
                echo "   Install: ${missing_deps[*]}"
                ;;
        esac
        exit 1
    fi

    print_color "${MINTY_GREEN}" "✅ All dependencies satisfied"
}

# Install for Arch Linux
install_arch() {
    print_color "${BIG_BLUE}" "🔨 Installing ZIM for Arch Linux..."

    cd /tmp
    if [ -d "zim" ]; then
        rm -rf zim
    fi

    print_color "${TEAL}" "📥 Cloning repository..."
    git clone https://github.com/ghostkellz/zim.git
    cd zim/release

    print_color "${TEAL}" "🔨 Building package..."
    makepkg -si --noconfirm

    print_color "${MINTY_GREEN}" "✅ ZIM installed successfully!"
}

# Install for Debian/Ubuntu
install_debian() {
    print_color "${BIG_BLUE}" "🔨 Installing ZIM for Debian/Ubuntu..."

    cd /tmp
    if [ -d "zim" ]; then
        rm -rf zim
    fi

    print_color "${TEAL}" "📥 Cloning repository..."
    git clone https://github.com/ghostkellz/zim.git
    cd zim/release/debian

    print_color "${TEAL}" "🔨 Building package..."
    ./build-deb.sh

    print_color "${TEAL}" "📦 Installing package..."
    sudo dpkg -i zim_0.1.0-1_amd64.deb
    sudo apt-get install -f -y

    print_color "${MINTY_GREEN}" "✅ ZIM installed successfully!"
}

# Install from source (universal)
install_from_source() {
    print_color "${BIG_BLUE}" "🔨 Building ZIM from source..."

    cd /tmp
    if [ -d "zim" ]; then
        rm -rf zim
    fi

    print_color "${TEAL}" "📥 Cloning repository..."
    git clone https://github.com/ghostkellz/zim.git
    cd zim

    print_color "${TEAL}" "🔨 Building binary..."
    zig build -Doptimize=ReleaseSafe

    print_color "${TEAL}" "📦 Installing to /usr/local/bin..."
    sudo cp zig-out/bin/zim /usr/local/bin/zim
    sudo chmod 755 /usr/local/bin/zim

    print_color "${MINTY_GREEN}" "✅ ZIM installed successfully!"
}

# Interactive menu
show_menu() {
    print_color "${TEAL}" "🎯 Detected distribution: ${BOLD}${DISTRO}${RESET}"
    echo ""
    print_color "${BIG_BLUE}" "Please select installation method:"
    echo ""

    case "$DISTRO" in
        arch|manjaro)
            print_color "${WHITE}" "  ${MINTY_GREEN}[1]${RESET} Install using PKGBUILD (recommended for Arch)"
            print_color "${WHITE}" "  ${MINTY_GREEN}[2]${RESET} Install from source"
            print_color "${WHITE}" "  ${MINTY_GREEN}[q]${RESET} Quit"
            ;;
        ubuntu|debian|pop)
            print_color "${WHITE}" "  ${MINTY_GREEN}[1]${RESET} Install using .deb package (recommended for Debian/Ubuntu)"
            print_color "${WHITE}" "  ${MINTY_GREEN}[2]${RESET} Install from source"
            print_color "${WHITE}" "  ${MINTY_GREEN}[q]${RESET} Quit"
            ;;
        fedora|rhel|centos)
            print_color "${WHITE}" "  ${MINTY_GREEN}[1]${RESET} Install from source"
            print_color "${WHITE}" "  ${MINTY_GREEN}[q]${RESET} Quit"
            print_color "${YELLOW}" ""
            print_color "${YELLOW}" "  ℹ️  RPM packages coming soon!"
            ;;
        *)
            print_color "${WHITE}" "  ${MINTY_GREEN}[1]${RESET} Install from source"
            print_color "${WHITE}" "  ${MINTY_GREEN}[q]${RESET} Quit"
            ;;
    esac

    echo ""
    print_color "${REGULAR_BLUE}" -n "Enter your choice: "
    read -r choice

    case "$choice" in
        1)
            case "$DISTRO" in
                arch|manjaro)
                    install_arch
                    ;;
                ubuntu|debian|pop)
                    install_debian
                    ;;
                *)
                    install_from_source
                    ;;
            esac
            ;;
        2)
            if [[ "$DISTRO" =~ ^(arch|manjaro|ubuntu|debian|pop)$ ]]; then
                install_from_source
            else
                print_color "${RED}" "❌ Invalid choice"
                exit 1
            fi
            ;;
        q|Q)
            print_color "${YELLOW}" "👋 Installation cancelled"
            exit 0
            ;;
        *)
            print_color "${RED}" "❌ Invalid choice"
            exit 1
            ;;
    esac
}

# Post-installation verification
verify_installation() {
    echo ""
    print_color "${BIG_BLUE}" "═══════════════════════════════════════════════════════════════"
    print_color "${TEAL}" "🔍 Verifying installation..."

    if command -v zim &> /dev/null; then
        local version=$(zim --version 2>&1 | head -n 1)
        print_color "${MINTY_GREEN}" "✅ ZIM is installed: ${version}"

        echo ""
        print_color "${REGULAR_BLUE}" "🚀 Quick Start:"
        print_color "${WHITE}" "   zim install 0.16.0       # Install Zig 0.16.0"
        print_color "${WHITE}" "   zim use 0.16.0           # Set as active version"
        print_color "${WHITE}" "   zim deps init myproject  # Initialize new project"
        print_color "${WHITE}" "   zim doctor               # Check system health"
        print_color "${WHITE}" "   zim --help               # Show all commands"

        echo ""
        print_color "${TEAL}" "📚 Documentation:"
        print_color "${WHITE}" "   https://github.com/ghostkellz/zim/tree/main/docs"

        echo ""
        print_color "${MINTY_GREEN}" "🎉 Happy Zig development!"
    else
        print_color "${RED}" "❌ Installation verification failed"
        print_color "${YELLOW}" "   Try running: which zim"
        exit 1
    fi
    print_color "${BIG_BLUE}" "═══════════════════════════════════════════════════════════════"
    echo ""
}

# Main installation flow
main() {
    # Clear screen for better presentation
    clear

    # Show logo
    print_logo

    # Checks
    check_root
    detect_distro
    check_dependencies

    echo ""

    # Show menu and install
    show_menu

    # Verify
    verify_installation
}

# Run main function
main
