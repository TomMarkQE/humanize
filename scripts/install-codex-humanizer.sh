#!/usr/bin/env bash
# Install or upgrade the Codex-only Codex Humanizer skill set.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_SKILLS_DIR="${CODEX_HOME:-${HOME}/.codex}/skills"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
DRY_RUN="false"
TARGET="codex"

SKILL_NAMES=(
  codex-humanizer
  codex-humanizer-gen-plan
  codex-humanizer-refine-plan
  codex-humanizer-rlcr
)
LEGACY_NATIVE_SKILLS=(humanize humanize-gen-plan humanize-refine-plan humanize-rlcr)
RUNTIME_FILES=(
  native-rlcr.py
  native_rlcr_common.py
  native_rlcr_state.py
  native_rlcr_run.py
  native_rlcr_review.py
  native_rlcr_runtime.py
  codex-humanizer-plan-io.py
)

usage() {
  cat <<'EOF'
Install Codex Humanizer skills for Codex.

Usage:
  scripts/install-codex-humanizer.sh [options]

Options:
  --target codex          Accepted for compatibility; no other target is supported
  --repo-root PATH        Repository checkout root (default: auto-detect)
  --skills-dir PATH       Alias for --codex-skills-dir
  --codex-skills-dir PATH Codex skills directory (default: ${CODEX_HOME:-~/.codex}/skills)
  --codex-config-dir PATH Codex config directory used for legacy hook cleanup
  --dry-run               Print actions without writing
  -h, --help              Show this help
EOF
}

log() { printf '[install-codex-humanizer] %s\n' "$*"; }
die() { printf '[install-codex-humanizer] Error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ -n "${2:-}" ]] || die "--target requires a value"
      [[ "$2" == "codex" ]] || die "this fork supports only --target codex"
      TARGET="$2"
      shift 2
      ;;
    --repo-root)
      [[ -n "${2:-}" ]] || die "--repo-root requires a value"
      REPO_ROOT="$2"
      shift 2
      ;;
    --skills-dir|--codex-skills-dir)
      [[ -n "${2:-}" ]] || die "$1 requires a value"
      CODEX_SKILLS_DIR="$2"
      shift 2
      ;;
    --codex-config-dir)
      [[ -n "${2:-}" ]] || die "--codex-config-dir requires a value"
      CODEX_CONFIG_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
SOURCE_SKILLS="$REPO_ROOT/codex-skills"
SOURCE_SCRIPTS="$REPO_ROOT/scripts"

[[ -d "$SOURCE_SKILLS" ]] || die "missing Codex skill source directory: $SOURCE_SKILLS"
[[ -d "$SOURCE_SCRIPTS" ]] || die "missing scripts directory: $SOURCE_SCRIPTS"
for skill in "${SKILL_NAMES[@]}"; do
  [[ -f "$SOURCE_SKILLS/$skill/SKILL.md" ]] || die "missing $SOURCE_SKILLS/$skill/SKILL.md"
done
for file in "${RUNTIME_FILES[@]}"; do
  [[ -f "$SOURCE_SCRIPTS/$file" ]] || die "missing runtime file: $SOURCE_SCRIPTS/$file"
done
command -v python3 >/dev/null 2>&1 || die "python3 is required"

sync_dir() {
  local src="$1" dst="$2" tmp
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN sync $src -> $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp -d "$(dirname "$dst")/.codex-humanizer-sync.XXXXXX")"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src/" "$tmp/"
  else
    cp -a "$src/." "$tmp/"
  fi
  rm -rf "$dst"
  mv "$tmp" "$dst"
}

legacy_native_install_present() {
  local runtime="$CODEX_SKILLS_DIR/humanize"
  [[ -f "$runtime/scripts/native-rlcr.py" ]] || return 1
  [[ -f "$runtime/SKILL.md" ]] || return 1
  grep -Eq 'Humanize for Codex|native_subagents|spawn_agent' "$runtime/SKILL.md"
}

remove_legacy_native_skill_names() {
  local skill path
  if ! legacy_native_install_present; then
    log "legacy native Humanize signature not found; preserving any unrelated humanize-* installation"
    return
  fi
  for skill in "${LEGACY_NATIVE_SKILLS[@]}"; do
    path="$CODEX_SKILLS_DIR/$skill"
    [[ -e "$path" ]] || continue
    if [[ "$DRY_RUN" == "true" ]]; then
      log "DRY-RUN remove legacy native skill: $path"
    else
      rm -rf "$path"
      log "removed legacy native skill: $path"
    fi
  done
}

hydrate_skills() {
  local runtime_root="$CODEX_SKILLS_DIR/codex-humanizer"
  local skill file tmp
  for skill in "${SKILL_NAMES[@]}"; do
    file="$CODEX_SKILLS_DIR/$skill/SKILL.md"
    [[ -f "$file" ]] || continue
    if [[ "$DRY_RUN" == "true" ]]; then
      log "DRY-RUN hydrate runtime root in $file"
      continue
    fi
    tmp="$(mktemp)"
    _CODEX_HUMANIZER_RUNTIME_ROOT="$runtime_root" \
      awk '{gsub(/\{\{HUMANIZE_RUNTIME_ROOT\}\}/, ENVIRON["_CODEX_HUMANIZER_RUNTIME_ROOT"]); print}' \
      "$file" > "$tmp"
    mv "$tmp" "$file"
  done
}

install_runtime() {
  local runtime_root="$CODEX_SKILLS_DIR/codex-humanizer"
  local scripts_dir="$runtime_root/scripts" file
  if [[ "$DRY_RUN" == "true" ]]; then
    for file in "${RUNTIME_FILES[@]}"; do
      log "DRY-RUN install runtime $SOURCE_SCRIPTS/$file -> $scripts_dir/$file"
    done
    return
  fi
  rm -rf "$scripts_dir"
  mkdir -p "$scripts_dir"
  for file in "${RUNTIME_FILES[@]}"; do
    cp "$SOURCE_SCRIPTS/$file" "$scripts_dir/$file"
  done
  chmod +x "$scripts_dir/native-rlcr.py" "$scripts_dir/codex-humanizer-plan-io.py"
}

remove_legacy_hooks() {
  local cleanup="$SOURCE_SCRIPTS/remove-codex-hooks.sh"
  [[ -f "$cleanup" ]] || { log "legacy hook cleanup helper absent; nothing to run"; return; }
  local args=(--codex-config-dir "$CODEX_CONFIG_DIR")
  [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
  bash "$cleanup" "${args[@]}"
}

log "repository root: $REPO_ROOT"
log "Codex skills directory: $CODEX_SKILLS_DIR"
log "Codex config directory: $CODEX_CONFIG_DIR"

[[ "$DRY_RUN" == "true" ]] || mkdir -p "$CODEX_SKILLS_DIR"
remove_legacy_native_skill_names
for skill in "${SKILL_NAMES[@]}"; do
  sync_dir "$SOURCE_SKILLS/$skill" "$CODEX_SKILLS_DIR/$skill"
done
install_runtime
hydrate_skills
remove_legacy_hooks

cat <<EOF

Codex Humanizer installed.

Skills:
  $CODEX_SKILLS_DIR/codex-humanizer
  $CODEX_SKILLS_DIR/codex-humanizer-gen-plan
  $CODEX_SKILLS_DIR/codex-humanizer-refine-plan
  $CODEX_SKILLS_DIR/codex-humanizer-rlcr

Runtime:
  $CODEX_SKILLS_DIR/codex-humanizer/scripts

Restart Codex so the renamed Skill metadata is reloaded.
EOF
