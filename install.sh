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
# Pin downloads to a released tag so the installer and the script it fetches move
# together — a given installer version lands a matching, checksum-verified script.
# Override to another version or bleeding-edge main via env:
#   MOUNTAINLABS_STATUSLINE_REF=main ./install.sh
# The release step bumps this default in lockstep with the tag (see RELEASING.md).
REF="${MOUNTAINLABS_STATUSLINE_REF:-v1.2.0}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

c(){ printf '\033[38;2;%sm%s\033[0m' "$1" "$2"; }        # color helper
# The installer's own small, cosmetic palette — deliberately separate from the
# runtime statusline palette in statusline.sh (which is user-overridable, #0007).
# Named UI_* so the two never masquerade as one shared source: this is installer
# chrome, not the statusline's colors.
UI_ACCENT='63;81;71'   # ▲ progress arrow
UI_ALERT='140;72;32'   # heading + warnings
UI_OK='110;150;120'    # ✓ success
UI_MUTE='120;120;115'  # secondary / footnote text
say(){ printf '%s %s\n' "$(c "$UI_ACCENT" '▲')" "$1"; }
ok(){  printf '%s %s\n' "$(c "$UI_OK" '✓')" "$1"; }
warn(){ printf '%s %s\n' "$(c "$UI_ALERT" '!')" "$1"; }

# sha256 of a file via whichever tool is present (BSD shasum on macOS, GNU
# sha256sum on Linux). Prints the bare hash, or returns non-zero if neither exists.
sha256(){
  if   command -v shasum   >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum   "$1" | awk '{print $1}'
  else return 127; fi
}

# Abort the install unless $DEST matches the statusline.sh hash in checksums file $1.
# A missing entry or absent sha256 tool downgrades to a warning (can't verify, but
# don't block); only a genuine mismatch is fatal.
verify(){
  local sums="$1" want have
  want="$(awk '$2 ~ /^\*?statusline\.sh$/ {print $1; exit}' "$sums" 2>/dev/null)"
  [ -n "$want" ] || { warn "No statusline.sh entry in checksums — skipping integrity check."; return 0; }
  have="$(sha256 "$DEST")" || { warn "No sha256 tool (shasum/sha256sum) — skipping integrity check."; return 0; }
  if [ "$want" != "$have" ]; then
    warn "Checksum mismatch for $DEST"
    echo "   expected $want"
    echo "   got      $have"
    echo "   Refusing to install a script that doesn't match its published checksum."
    exit 1
  fi
  ok "Verified checksum (sha256)"
}

printf '\n%s\n\n' "$(c "$UI_ALERT" 'MountainLabs statusline')"

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
# Prefer local files (a clone); fall back to fetching the pinned ref. Either way,
# we grab a matching checksums.txt and verify before trusting the script.
tmp_sums=""
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/statusline.sh" ]; then
  cp "$SRC_DIR/statusline.sh" "$DEST"
  say "Installed script from clone → $DEST"
  sums_src="$SRC_DIR/checksums.txt"
else
  curl -fsSL "$RAW/statusline.sh" -o "$DEST"
  say "Downloaded script ($REF) → $DEST"
  tmp_sums="$(mktemp)"
  if curl -fsSL "$RAW/checksums.txt" -o "$tmp_sums" 2>/dev/null; then sums_src="$tmp_sums"; else sums_src=""; fi
fi
chmod +x "$DEST"

if [ -n "$sums_src" ] && [ -f "$sums_src" ]; then
  verify "$sums_src"
else
  warn "No checksums.txt available for $REF — could not verify integrity."
fi
[ -n "$tmp_sums" ] && rm -f "$tmp_sums"

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
printf '\n%s\n' "$(c "$UI_OK" 'Done.')"
c "$UI_MUTE" 'Next:'; printf '\n'
echo "  1. Install a Nerd Font for the glyphs, e.g.  brew install --cask font-jetbrains-mono-nerd-font"
echo "     then set your terminal font to it (JetBrainsMono Nerd Font)."
echo "  2. Restart Claude Code (or start a new session) to see the bar."
echo "  3. Optional MountainLabs terminal theme: examples/ghostty.config"
printf '\n%s\n\n' "$(c "$UI_MUTE" 'Note: a project .claude/settings.json can override the user-level statusLine — see the README.')"
