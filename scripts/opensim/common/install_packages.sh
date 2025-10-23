#!/bin/bash
# Common package installation script
# Installs system packages required for building OpenSim
#
# Usage:
#   install_packages.sh [--deps-only]
#
# This script reads package lists from packages.yaml

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$SCRIPT_DIR/packages.yaml"

# Check if packages.yaml exists
if [ ! -f "$PACKAGES_FILE" ]; then
    echo "Error: packages.yaml not found at $PACKAGES_FILE"
    exit 1
fi

# Simple YAML parser function (reads package list for a given manager)
# Args: $1 = package_manager (e.g., "dnf", "apt", "brew")
get_packages() {
    local manager="$1"
    local in_section=0
    local packages=()

    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check if we're entering the right section
        if [[ "$line" =~ ^[[:space:]]*${manager}:[[:space:]]*$ ]]; then
            in_section=1
            continue
        fi

        # Check if we're leaving the section (another top-level key)
        if [[ "$line" =~ ^[[:space:]]*[a-z_]+:[[:space:]]*$ ]] && [ $in_section -eq 1 ]; then
            break
        fi

        # Extract package name if in section
        if [ $in_section -eq 1 ]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.+)$ ]]; then
                local pkg="${BASH_REMATCH[1]}"
                # Remove any trailing comments or colons
                pkg=$(echo "$pkg" | sed 's/[[:space:]]*#.*//' | sed 's/:.*//')
                packages+=("$pkg")
            fi
        fi
    done < <(grep -A 1000 "^linux:" "$PACKAGES_FILE" || true)

    echo "${packages[@]}"
}

# Detect package manager and platform
detect_platform() {
    if command -v apk >/dev/null 2>&1; then
        echo "apk"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Install packages for Linux
install_linux_packages() {
    local manager="$1"
    shift
    local packages=("$@")

    if [ ${#packages[@]} -eq 0 ]; then
        echo "No packages to install"
        return 0
    fi

    echo "Installing ${#packages[@]} packages using $manager..."
    echo "Packages: ${packages[*]}"

    case "$manager" in
        apk)
            apk add --no-cache "${packages[@]}"
            ;;
        dnf)
            # Try to install packages, allowing some to fail
            for package in "${packages[@]}"; do
                echo "Installing $package..."
                if ! dnf install -y "$package" 2>/dev/null; then
                    echo "Warning: Failed to install $package, continuing..."
                fi
            done
            ;;
        yum)
            # Try to install packages, allowing some to fail
            for package in "${packages[@]}"; do
                echo "Installing $package..."
                if ! yum install -y "$package" 2>/dev/null; then
                    echo "Warning: Failed to install $package, continuing..."
                fi
            done
            ;;
        apt)
            if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
                sudo apt-get update && sudo apt-get install -y "${packages[@]}"
            elif [ "$EUID" -eq 0 ]; then
                apt-get update && apt-get install -y "${packages[@]}"
            else
                echo "Warning: Cannot install packages - no sudo access and not running as root"
                return 1
            fi
            ;;
        *)
            echo "Unsupported package manager: $manager"
            return 1
            ;;
    esac
}

# Install packages for macOS
install_macos_packages() {
    local packages=("pkgconfig" "autoconf" "libtool" "automake" "wget" "pcre" "doxygen" "python" "git" "ninja" "cmake" "gcc")

    echo "Checking Homebrew packages..."

    # Check which packages are missing
    local missing_packages=()
    for package in "${packages[@]}"; do
        if ! brew list "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done

    # Only install if there are missing packages
    if [ ${#missing_packages[@]} -eq 0 ]; then
        echo "✓ All required Homebrew packages are already installed."
    else
        echo "Missing packages: ${missing_packages[*]}"
        echo "Installing build dependencies..."
        # Use architecture-specific brew commands
        if [[ $(uname -m) == "arm64" ]]; then
            arch -arm64 brew install "${missing_packages[@]}"
        else
            brew install "${missing_packages[@]}"
        fi
    fi

    # Check and install Java 8
    echo "Checking Java 8 installation..."
    if /usr/libexec/java_home -v 1.8 &>/dev/null; then
        echo "✓ Java 8 is already installed."
        export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
    else
        echo "Installing Java 8..."
        if [[ $(uname -m) == "arm64" ]]; then
            arch -arm64 brew install --cask temurin@8
        else
            brew install --cask temurin@8
        fi
        export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
    fi

    echo "JAVA_HOME: $JAVA_HOME"
}

# Main installation logic
main() {
    local platform=$(detect_platform)

    echo "=== Installing System Packages ==="
    echo "Detected platform: $platform"

    case "$platform" in
        apk|dnf|yum|apt)
            # Read packages from YAML
            local packages=($(get_packages "$platform"))

            # Check which packages are missing
            local missing_packages=()

            if [ "$platform" = "apk" ]; then
                for package in "${packages[@]}"; do
                    if ! apk info -e "$package" >/dev/null 2>&1; then
                        missing_packages+=("$package")
                    fi
                done
            elif [ "$platform" = "dnf" ] || [ "$platform" = "yum" ]; then
                for package in "${packages[@]}"; do
                    if ! rpm -q "$package" >/dev/null 2>&1; then
                        missing_packages+=("$package")
                    fi
                done
            elif [ "$platform" = "apt" ]; then
                for package in "${packages[@]}"; do
                    if ! dpkg -l | grep -q "^ii  $package\(:\|[[:space:]]\)" 2>/dev/null; then
                        missing_packages+=("$package")
                    fi
                done
            fi

            # Only install if there are missing packages
            if [ ${#missing_packages[@]} -eq 0 ]; then
                echo "✓ All required system dependencies are already installed."
            else
                install_linux_packages "$platform" "${missing_packages[@]}"
            fi
            ;;
        brew)
            install_macos_packages
            ;;
        unknown)
            echo "Warning: No supported package manager found (apk/dnf/yum/apt-get/brew)"
            echo "Please install dependencies manually. See packages.yaml for package lists."
            return 1
            ;;
    esac

    echo "✓ Package installation complete"
}

# Run main function
main "$@"
