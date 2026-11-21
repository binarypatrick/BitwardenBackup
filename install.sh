#!/bin/bash

# Installs the Bitwarden CLI (`bw`) into /usr/local/bin.
set -euo pipefail

DOWNLOAD_URL='https://bitwarden.com/download/?app=cli&platform=linux'
INSTALL_DIR='/usr/local/bin'

# Writing to /usr/local/bin usually needs root. Elevate with sudo when needed
# instead of failing with a confusing "permission denied" from unzip.
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo "This script needs root to write to $INSTALL_DIR (and sudo was not found)." >&2
        echo "Re-run as root." >&2
        exit 1
    fi
fi

for cmd in wget unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command '$cmd' is not installed." >&2
        exit 1
    fi
done

# Work in a temp dir that is always cleaned up, even on failure.
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading Bitwarden CLI..."
wget -q "$DOWNLOAD_URL" -O "$WORKDIR/bw.zip"

# Sanity-check that we actually downloaded a zip (e.g. not an HTML error page).
if ! unzip -tq "$WORKDIR/bw.zip" >/dev/null 2>&1; then
    echo "Downloaded file is not a valid zip archive; aborting." >&2
    exit 1
fi

echo "Installing to $INSTALL_DIR..."
$SUDO unzip -oq "$WORKDIR/bw.zip" -d "$INSTALL_DIR"
$SUDO chmod +x "$INSTALL_DIR/bw"

echo "Bitwarden CLI installed: $("$INSTALL_DIR/bw" --version 2>/dev/null || echo "$INSTALL_DIR/bw")"
