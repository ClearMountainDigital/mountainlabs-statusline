#!/usr/bin/env bash
# ============================================================================
# MountainLabs statusline — installer
# https://github.com/ClearMountainDigital/mountainlabs-statusline
#
# Copies statusline.sh into your Claude Code config dir and wires up the
# statusLine setting (backing up anything it replaces). Safe to re-run.
#
# From a clone:   ./install.sh
# One-liner:      curl -fsSL https://raw.githubusercontent.com/ClearMountainDigital/mountainlabs-statusline/main/install.sh | bash
# ============================================================================
set -euo pipefail

REPO="ClearMountainDigital/mountainlabs-statusline"
RAW="https://raw.githubusercontent.com/$REPO/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

c(){ printf '\033[38;2;%sm%s\033[0m' "$1" "$2"; }        # color helper
FOREST='63;81;71'; RUST='140;72;32'; SAGE='110;150;120'; DIM='120;120;115'
say(){ printf '%s %s\n' "$(c "$FOREST" '▲')" "$1"; }
ok(){  printf '%s %s\n' "$(c "$SAGE" '✓')" "$1"; }
warn(){ printf '%s %s\n' "$(c "$RUST" '!')" "$1"; }

printf '\n%s\n\n' "$(c "$RUST" 'MountainLabs statusline')"

# --- dependency check -------------------------------------------------------
missing=""
for dep in jq git awk; do command -v "$dep" >/dev/null 2>&1 || missing="$missing $dep"; done
if [ -n "$missing" ]; then
  warn "Missing required tools:$missing"
  echo "   Install them first, e.g.  brew install$missing"
  [ "${missing// /}" = "jq" ] || exit 1   # jq alone we can work around; anything else, stop
fi

mkdir -p "$CLAUDE_DIR"

# --- install the script -----------------------------------------------------
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/statusline.sh" ]; then
  cp "$SRC_DIR/statusline.sh" "$DEST"
  say "Installed script from clone → $DEST"
else
  curl -fsSL "$RAW/statusline.sh" -o "$DEST"
  say "Downloaded script → $DEST"
fi
chmod +x "$DEST"

# --- wire up settings.json --------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "$SETTINGS.bak-statusline"
    say "Backed up existing settings → $SETTINGS.bak-statusline"
    tmp="$(mktemp)"
    jq --arg cmd "$DEST" '.statusLine = {type:"command", command:$cmd, padding:0}' \
      "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  else
    jq -n --arg cmd "$DEST" '{statusLine:{type:"command", command:$cmd, padding:0}}' > "$SETTINGS"
  fi
  ok "Wired statusLine into $SETTINGS"
else
  warn "jq not found — add this to $SETTINGS yourself:"
  printf '   %s\n' '"statusLine": { "type": "command", "command": "'"$DEST"'", "padding": 0 }'
fi

# --- done -------------------------------------------------------------------
printf '\n%s\n' "$(c "$SAGE" 'Done.')"
echo "$(c "$DIM" 'Next:')"
echo "  1. Install a Nerd Font for the glyphs, e.g.  brew install --cask font-jetbrains-mono-nerd-font"
echo "     then set your terminal font to it (JetBrainsMono Nerd Font)."
echo "  2. Restart Claude Code (or start a new session) to see the bar."
echo "  3. Optional MountainLabs terminal theme: examples/ghostty.config"
printf '\n%s\n\n' "$(c "$DIM" 'Note: a project .claude/settings.json can override the user-level statusLine — see the README.')"
