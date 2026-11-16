#!/usr/bin/env bash
# Isola installer for macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/Natuworkguy/Isola/main/install.sh | bash
#   ... | bash -s -- --dev         the dev branch, built from source, where changes land before a release
#   ... | bash -s -- --uninstall   take it back out
#
# Installs the latest release's Isola.app. Where there is none (or with --dev), it builds Isola from source instead,
# first installing the Xcode Command Line Tools if this Mac does not have them. Isola goes in /Applications (or
# ~/Applications without permission to write there), cleared to open without the "unidentified developer" prompt, and
# starts. Running it again updates.
set -euo pipefail
REPO="Natuworkguy/Isola"
BRANCH="main"; DEV=""
say() { printf '%s\n' "$*"; }

for arg in "$@"; do
  case "$arg" in
    --dev) BRANCH="dev"; DEV=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) say "Unknown option: $arg (use --dev or --uninstall)"; exit 1 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  say "Isola is for macOS and Windows. On Windows, run this in PowerShell:"
  say "  irm https://raw.githubusercontent.com/$REPO/main/install.ps1 | iex"
  exit 1
fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "${major:-0}" -lt 14 ]; then
  say "Isola needs macOS 14 or later; this Mac has $(sw_vers -productVersion)."
  exit 1
fi

DEST="/Applications"; [ -w "$DEST" ] || DEST="$HOME/Applications"
quit_isola() { osascript -e 'tell application "Isola" to quit' >/dev/null 2>&1 || true; sleep 1; pkill -x Isola 2>/dev/null || true; }

if [ -n "${UNINSTALL:-}" ]; then
  quit_isola
  removed=""
  for d in /Applications "$HOME/Applications"; do
    if [ -d "$d/Isola.app" ]; then rm -rf "$d/Isola.app" && removed=1 && say "Removed $d/Isola.app."; fi
  done
  [ -n "$removed" ] || say "Isola is not installed."
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
app=""

# 1. The latest release, ready built (not for --dev)
if [ -z "$DEV" ]; then
  say "Downloading the latest release of Isola."
  if curl -fsSL -o "$tmp/Isola-macOS.zip" "https://github.com/$REPO/releases/latest/download/Isola-macOS.zip" 2>/dev/null; then
    ditto -x -k "$tmp/Isola-macOS.zip" "$tmp/release" && [ -d "$tmp/release/Isola.app" ] && app="$tmp/release/Isola.app"
  fi
  [ -n "$app" ] || say "The latest release has no Mac download yet, so Isola will be built from source."
fi

# 2. Otherwise, built from source with the Xcode Command Line Tools
if [ -z "$app" ]; then
  if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    say "Isola is built with the Xcode Command Line Tools, which this Mac does not have yet."
    say "Asking macOS to install them: choose Install in the window that opens. This can take a while."
    xcode-select --install >/dev/null 2>&1 || true
    waited=0
    until xcode-select -p >/dev/null 2>&1 && xcrun --find swift >/dev/null 2>&1; do
      sleep 10; waited=$((waited + 10))
      [ $((waited % 60)) -eq 0 ] && say "Still waiting for the Command Line Tools to finish installing ($((waited / 60)) min)."
      if [ "$waited" -ge 3600 ]; then say "The Command Line Tools did not finish installing within an hour. Install them, then run this again."; exit 1; fi
    done
    say "The Command Line Tools are installed."
  fi
  say "Downloading Isola's source ($BRANCH)."
  curl -fsSL "https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz" | tar -xz -C "$tmp"
  src="$(find "$tmp" -maxdepth 1 -type d -name 'Isola-*' | head -1)"
  [ -n "$src" ] || { say "Could not unpack Isola's source."; exit 1; }
  say "Building Isola. The first build takes a few minutes."
  (cd "$src/macOS" && ./build_app.sh)
  app="$src/macOS/build/Isola.app"
  [ -d "$app" ] || { say "The build did not make Isola.app."; exit 1; }
fi

# 3. Into Applications, cleared to open, and started
quit_isola
mkdir -p "$DEST"
rm -rf "$DEST/Isola.app"
ditto "$app" "$DEST/Isola.app"
xattr -dr com.apple.quarantine "$DEST/Isola.app" 2>/dev/null || true
say "Isola is installed in $DEST$([ -n "$DEV" ] && echo ' (the dev version)')."
open "$DEST/Isola.app"
say "It is running: look at the top of your screen. Its settings are under the island icon in the menu bar."
