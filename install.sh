#!/usr/bin/env bash
#
# Link this kit into ~/.claude so its skills are available in every project.
#
#   ./install.sh            symlink (default) — edits here take effect immediately
#   ./install.sh --copy     copy instead, for a machine where symlinks are awkward
#   ./install.sh --dry-run  print what would happen and change nothing
#
# Idempotent. It will not clobber a real file it did not create: anything already
# present that is not a link into this kit is reported and skipped, so an existing
# ~/.claude/CLAUDE.md or a same-named skill has to be dealt with deliberately.

set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
MODE=symlink
DRY=

for arg in "$@"; do
  case "$arg" in
    --copy)    MODE=copy ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
run() { if [ -n "$DRY" ]; then say "would: $*"; else "$@"; fi; }

# $1 = source path inside the kit, $2 = destination path under ~/.claude
link_one() {
  local src="$1" dst="$2" tilde="~" name; name="${2/#$HOME/$tilde}"

  if [ -L "$dst" ]; then
    local current; current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then say "ok       $name (already linked)"; return; fi
    if [ "$current" != "${current#$KIT}" ]; then
      run rm "$dst"; say "relinked $name (was $current)"
    elif [ ! -e "$dst" ]; then
      # Dangling: whatever it pointed at is gone, so there is nothing to lose. This is
      # the normal state after the kit directory is renamed or moved, and refusing to
      # touch it would leave the skill silently uninstalled.
      run rm "$dst"; say "relinked $name (was dangling: $current)"
    else
      say "SKIP     $name — symlink to something else: $current"; return
    fi
  elif [ -e "$dst" ]; then
    say "SKIP     $name — exists and was not created by this kit. Move it aside, then rerun."
    return
  fi

  if [ "$MODE" = copy ]; then
    run cp -R "$src" "$dst"; say "copied   $name"
  else
    run ln -s "$src" "$dst"; say "linked   $name"
  fi
}

run mkdir -p "$DEST/skills"

for skill in "$KIT"/skills/*/; do
  link_one "${skill%/}" "$DEST/skills/$(basename "$skill")"
done

link_one "$KIT/CLAUDE.md" "$DEST/CLAUDE.md"

say
say "Done. Skills load at the start of a session, so restart Claude Code to pick up new ones."
if [ "$MODE" = copy ]; then
  say "Copied, not linked: edits in this repo will NOT reach ~/.claude until you rerun this."
fi
