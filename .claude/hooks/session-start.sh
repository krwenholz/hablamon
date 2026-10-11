#!/bin/bash
# Installs mise, the Swift toolchain from mise.toml, and package dependencies
# so `mise run verify` works in Claude Code cloud sessions (Linux).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Shared libraries the swift.org Linux toolchain needs (per swiftly's install notes).
deps=(libcurl4-openssl-dev libxml2-dev libz3-dev)
if ! dpkg -s "${deps[@]}" >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq "${deps[@]}"
fi

if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

mise trust --quiet "$CLAUDE_PROJECT_DIR/mise.toml"
mise install
swift build

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$HOME/.local/bin:$HOME/.local/share/mise/shims:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
