#!/usr/bin/env bash
# install.sh — TachTone installer
#
# Usage:
#   ./install.sh              # install app + Claude Code hooks
#   ./install.sh --hooks-only # hooks only (skip app copy)
#   ./install.sh --app-only   # app only (skip hooks)
#
# The app is copied from build/DerivedData (run `make` first) or, if that
# isn't present, from the same directory as this script (e.g. a mounted DMG).

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
APP_NAME="TachToneMac"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_APP="$SCRIPT_DIR/build/DerivedData/Build/Products/Release/$APP_NAME.app"
SCRIPT_APP="$SCRIPT_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
CLAUDE_DIR="$HOME/.claude"
HOOK_SCRIPT_SRC="$SCRIPT_DIR/hooks/token_coins.py"
HOOK_SCRIPT_DST="$CLAUDE_DIR/token_coins.py"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
INSTALL_APP=true
INSTALL_HOOKS=true

for arg in "$@"; do
  case $arg in
    --hooks-only) INSTALL_APP=false ;;
    --app-only)   INSTALL_HOOKS=false ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "  $*"; }
success() { echo "✓ $*"; }
warn()    { echo "⚠ $*"; }
fail()    { echo "✗ $*" >&2; exit 1; }

confirm() {
  local prompt="$1"
  read -r -p "  $prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------------------------------------------------------------------------
# 1. Install app
# ---------------------------------------------------------------------------
if $INSTALL_APP; then
  echo ""
  echo "── App ──────────────────────────────────────────────"

  # Find the .app to install
  if [[ -d "$BUILD_APP" ]]; then
    APP_SRC="$BUILD_APP"
    info "Found built app at: $APP_SRC"
  elif [[ -d "$SCRIPT_APP" ]]; then
    APP_SRC="$SCRIPT_APP"
    info "Found app alongside installer: $APP_SRC"
  else
    fail "No $APP_NAME.app found. Run 'make' first, or place $APP_NAME.app next to install.sh."
  fi

  DEST="$INSTALL_DIR/$APP_NAME.app"

  if [[ -d "$DEST" ]]; then
    warn "$APP_NAME.app is already installed."
    confirm "Replace it?" || { info "Skipping app install."; INSTALL_APP=false; }
  fi

  if $INSTALL_APP; then
    info "Copying to $INSTALL_DIR…"
    rm -rf "$DEST"
    cp -R "$APP_SRC" "$DEST"
    success "Installed $APP_NAME.app to $INSTALL_DIR"
  fi
fi

# ---------------------------------------------------------------------------
# 2. Install Claude Code hooks
# ---------------------------------------------------------------------------
if $INSTALL_HOOKS; then
  echo ""
  echo "── Claude Code Hooks ────────────────────────────────"

  # 2a. Copy token_coins.py
  if [[ ! -f "$HOOK_SCRIPT_SRC" ]]; then
    fail "hooks/token_coins.py not found at $HOOK_SCRIPT_SRC"
  fi

  mkdir -p "$CLAUDE_DIR"
  cp "$HOOK_SCRIPT_SRC" "$HOOK_SCRIPT_DST"
  chmod +x "$HOOK_SCRIPT_DST"
  success "Copied token_coins.py → $HOOK_SCRIPT_DST"

  # 2b. Merge hooks into ~/.claude/settings.json via Python
  info "Merging hooks into $SETTINGS_FILE…"

  python3 - "$SETTINGS_FILE" "$HOOK_SCRIPT_DST" <<'PYEOF'
import json, os, sys

settings_path = sys.argv[1]
coins_script  = sys.argv[2]

# Load or create settings
if os.path.exists(settings_path):
    with open(settings_path) as f:
        try:
            settings = json.load(f)
        except json.JSONDecodeError:
            settings = {}
else:
    settings = {}

hooks = settings.setdefault("hooks", {})

# All TachTone hook entries
TACHTONE = {
    "Notification": {
        "hooks": [{
            "type": "command",
            "command": "python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b\"need attention\",(\"127.0.0.1\",9876)); s.close()'",
            "async": True
        }]
    },
    "UserPromptSubmit": {
        "hooks": [{
            "type": "command",
            "command": "python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b\"user_prompt_submit\",(\"127.0.0.1\",9876)); s.close()'",
            "async": True
        }]
    },
    "Stop": {
        "hooks": [{
            "type": "command",
            "command": f"python3 {coins_script}",
            "async": True
        }]
    },
    "PreToolUse": {
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": "python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b\"pre_tool_use\",(\"127.0.0.1\",9876)); s.close()'",
            "async": True
        }]
    },
    "PostToolUse": {
        "matcher": "",
        "hooks": [{
            "type": "command",
            "command": "python3 -c 'import socket; s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.sendto(b\"post_tool_use\",(\"127.0.0.1\",9876)); s.close()'",
            "async": True
        }]
    },
}

added   = []
skipped = []

for event, entry in TACHTONE.items():
    existing = hooks.get(event, [])
    # Detect any existing TachTone entry by port 9876 or token_coins marker
    already = any(
        any("9876" in h.get("command", "") or "token_coins" in h.get("command", "")
            for h in block.get("hooks", []))
        for block in existing
    )
    if already:
        skipped.append(event)
    else:
        existing.append(entry)
        hooks[event] = existing
        added.append(event)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

if added:
    print(f"  Added hooks: {', '.join(added)}")
if skipped:
    print(f"  Already present (skipped): {', '.join(skipped)}")
PYEOF

  success "Claude Code hooks configured"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "────────────────────────────────────────────────────"
echo "✓ TachTone install complete."
echo ""
echo "  Launch TachTone from /Applications or Spotlight."
echo "  Use Claude Code normally — coin sounds will play"
echo "  after each response based on token cost."
echo ""
