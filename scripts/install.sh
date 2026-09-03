#!/usr/bin/env bash
# Link the skills in this repository into every agent's skill directory.
#
# Symlinks, not copies: `git pull` here updates every agent at once.
#
# Usage:
#   scripts/install.sh                    link all skills into all detected agents
#   scripts/install.sh kicad ardupilot    link only these skills
#   scripts/install.sh --dry-run          show what would happen
#   scripts/install.sh --uninstall        remove links this repo created
#   scripts/install.sh --target DIR       add a skills directory (repeatable)
#   scripts/install.sh --list             show detected agents and linked skills

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

DRY_RUN=0
UNINSTALL=0
LIST_ONLY=0
declare -a WANTED=()
declare -a EXTRA_TARGETS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --list)      LIST_ONLY=1 ;;
    --target)    shift; [ $# -gt 0 ] || { echo "error: --target needs a directory" >&2; exit 2; }
                 EXTRA_TARGETS+=("$1") ;;
    -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "error: unknown option $1" >&2; exit 2 ;;
    *)           WANTED+=("$1") ;;
  esac
  shift
done

# --- discover skills ------------------------------------------------------

declare -a SKILLS=()
for dir in "$SKILLS_DIR"/*/; do
  [ -f "$dir/SKILL.md" ] || continue
  SKILLS+=("$(basename "$dir")")
done
if [ ${#SKILLS[@]} -eq 0 ]; then
  echo "error: no skills found in $SKILLS_DIR" >&2
  exit 2
fi

if [ ${#WANTED[@]} -gt 0 ]; then
  declare -a SELECTED=()
  for want in "${WANTED[@]}"; do
    found=0
    for have in "${SKILLS[@]}"; do
      [ "$want" = "$have" ] && { SELECTED+=("$want"); found=1; break; }
    done
    [ "$found" -eq 1 ] || { echo "error: no such skill '$want'. Available: ${SKILLS[*]}" >&2; exit 2; }
  done
  SKILLS=("${SELECTED[@]}")
fi

# --- discover targets -----------------------------------------------------
# Claude Code reads ~/.claude/skills; the Agent Skills standard (Codex and
# others) reads ~/.agents/skills. Only link into a directory whose agent is
# actually present, so we don't scatter directories for tools you don't use.

declare -a TARGETS=()
declare -a TARGET_LABELS=()

add_target() {
  local label="$1" dir="$2"
  TARGETS+=("$dir")
  TARGET_LABELS+=("$label")
}

[ -d "$HOME/.claude" ] && add_target "Claude Code" "$HOME/.claude/skills"
{ [ -d "$HOME/.agents" ] || command -v codex >/dev/null 2>&1; } && add_target "Agent Skills (~/.agents)" "$HOME/.agents/skills"
for extra in ${EXTRA_TARGETS+"${EXTRA_TARGETS[@]}"}; do
  add_target "custom" "$extra"
done

if [ ${#TARGETS[@]} -eq 0 ]; then
  echo "No agent skill directories detected."
  echo "Pass --target DIR to link somewhere explicitly, or install Claude Code first."
  exit 1
fi

# --- report ---------------------------------------------------------------

echo "Repository: $REPO_ROOT"
echo
echo "Agents"
for i in "${!TARGETS[@]}"; do
  printf '  %-26s %s\n' "${TARGET_LABELS[$i]}" "${TARGETS[$i]}"
done
echo
echo "Skills"
for skill in "${SKILLS[@]}"; do
  printf '  %s\n' "$skill"
done
echo

if [ "$LIST_ONLY" -eq 1 ]; then
  echo "Links"
  for target in "${TARGETS[@]}"; do
    for skill in "${SKILLS[@]}"; do
      link="$target/$skill"
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$SKILLS_DIR/$skill" ]; then
        printf '  ok       %s\n' "$link"
      elif [ -L "$link" ]; then
        printf '  foreign  %s -> %s\n' "$link" "$(readlink "$link")"
      elif [ -e "$link" ]; then
        printf '  conflict %s (not a symlink)\n' "$link"
      else
        printf '  missing  %s\n' "$link"
      fi
    done
  done
  exit 0
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '  would %s\n' "$*"
  else
    "$@"
  fi
}

linked=0 skipped=0 removed=0
for target in "${TARGETS[@]}"; do
  if [ "$UNINSTALL" -eq 0 ]; then
    [ -d "$target" ] || run mkdir -p "$target"
  fi
  for skill in "${SKILLS[@]}"; do
    link="$target/$skill"
    src="$SKILLS_DIR/$skill"

    if [ "$UNINSTALL" -eq 1 ]; then
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
        run rm "$link"
        echo "  removed  $link"
        removed=$((removed + 1))
      fi
      continue
    fi

    if [ -L "$link" ]; then
      if [ "$(readlink "$link")" = "$src" ]; then
        echo "  ok       $link"
        skipped=$((skipped + 1))
        continue
      fi
      echo "  replaced $link (was -> $(readlink "$link"))"
      run rm "$link"
    elif [ -e "$link" ]; then
      # A real directory here is somebody else's skill. Never clobber it.
      echo "  SKIP     $link exists and is not a symlink — remove it by hand to link this repo's version" >&2
      skipped=$((skipped + 1))
      continue
    fi

    run ln -s "$src" "$link"
    echo "  linked   $link"
    linked=$((linked + 1))
  done
done

echo
if [ "$UNINSTALL" -eq 1 ]; then
  echo "Removed $removed link(s)."
else
  echo "Linked $linked, already present $skipped."
  [ "$DRY_RUN" -eq 1 ] && echo "(dry run — nothing was written)"
fi
