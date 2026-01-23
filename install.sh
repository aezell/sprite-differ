#!/bin/bash
# sprite-differ installer
# Usage: curl -fsSL https://raw.githubusercontent.com/aezell/sprite-differ/main/install.sh | bash

set -e

REPO="aezell/sprite-differ"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
BINARY_NAME="sprite-differ"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
    echo -e "${GREEN}==>${NC} $1"
}

warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

error() {
    echo -e "${RED}Error:${NC} $1"
    exit 1
}

# Detect OS and architecture
detect_platform() {
    local os arch

    case "$(uname -s)" in
        Linux*)  os="linux" ;;
        Darwin*) os="macos" ;;
        *)       error "Unsupported operating system: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64)  arch="x86_64" ;;
        amd64)   arch="x86_64" ;;
        arm64)   arch="aarch64" ;;
        aarch64) arch="aarch64" ;;
        *)       error "Unsupported architecture: $(uname -m)" ;;
    esac

    echo "${os}_${arch}"
}

# Get latest release version
get_latest_version() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" |
        grep '"tag_name":' |
        sed -E 's/.*"([^"]+)".*/\1/'
}

main() {
    info "Installing sprite-differ..."

    # Detect platform
    local platform
    platform=$(detect_platform)
    info "Detected platform: ${platform}"

    # Get latest version
    local version
    version=$(get_latest_version)
    if [ -z "$version" ]; then
        error "Could not determine latest version. Check https://github.com/${REPO}/releases"
    fi
    info "Latest version: ${version}"

    # Construct download URL
    local download_url="https://github.com/${REPO}/releases/download/${version}/${BINARY_NAME}-${platform}"
    info "Downloading from: ${download_url}"

    # Create install directory if needed
    mkdir -p "${INSTALL_DIR}"

    # Download binary
    local tmp_file
    tmp_file=$(mktemp)
    if ! curl -fsSL "${download_url}" -o "${tmp_file}"; then
        rm -f "${tmp_file}"
        error "Failed to download binary. Check if release exists for your platform."
    fi

    # Install binary
    chmod +x "${tmp_file}"
    mv "${tmp_file}" "${INSTALL_DIR}/${BINARY_NAME}"

    info "Installed ${BINARY_NAME} to ${INSTALL_DIR}/${BINARY_NAME}"

    # Check if install dir is in PATH
    if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
        warn "${INSTALL_DIR} is not in your PATH"
        echo ""
        echo "Add it to your shell profile:"
        echo ""
        echo "  export PATH=\"\$PATH:${INSTALL_DIR}\""
        echo ""
    fi

    # Verify installation
    if command -v "${BINARY_NAME}" &> /dev/null; then
        info "Installation complete! Run 'sprite-differ --help' to get started."
    else
        info "Installation complete! You may need to restart your shell or add ${INSTALL_DIR} to your PATH."
    fi
}

main "$@"
