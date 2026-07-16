#!/usr/bin/env bash
# Remove Humanize Codex-native assets and legacy managed Codex artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_SKILLS_DIR="${HUMANIZE_CODEX_SKILLS_DIR:-${HOME}/.agents/skills}"
CODEX_AGENTS_DIR=""
COMMAND_BIN_DIR="${HUMANIZE_COMMAND_BIN_DIR:-${HOME}/.local/bin}"
SKILLS_EXPLICIT=false
AGENTS_EXPLICIT=false
COMMAND_BIN_EXPLICIT=false
DRY_RUN=false

usage() {
    cat <<'USAGE'
Uninstall Humanize's Codex-native skills, agents, and legacy managed hooks.

Usage: scripts/uninstall-skills-codex.sh [options]

Options:
  --codex-skills-dir PATH  Installed skills directory
  --codex-config-dir PATH  Codex config directory
  --codex-agents-dir PATH  Installed custom agent directory
  --command-bin-dir PATH   Legacy shim directory to clean
  --dry-run                Print changes without writing
  -h, --help               Show this help
USAGE
}

die() {
    printf '[uninstall-codex-native] Error: %s\n' "$*" >&2
    exit 1
}

log() {
    printf '[uninstall-codex-native] %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --codex-skills-dir)
            [[ -n "${2:-}" ]] || die "--codex-skills-dir requires a value"
            CODEX_SKILLS_DIR="$2"
            SKILLS_EXPLICIT=true
            shift 2
            ;;
        --codex-config-dir)
            [[ -n "${2:-}" ]] || die "--codex-config-dir requires a value"
            CODEX_CONFIG_DIR="$2"
            shift 2
            ;;
        --codex-agents-dir)
            [[ -n "${2:-}" ]] || die "--codex-agents-dir requires a value"
            CODEX_AGENTS_DIR="$2"
            AGENTS_EXPLICIT=true
            shift 2
            ;;
        --command-bin-dir)
            [[ -n "${2:-}" ]] || die "--command-bin-dir requires a value"
            COMMAND_BIN_DIR="$2"
            COMMAND_BIN_EXPLICIT=true
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

command -v python3 >/dev/null 2>&1 || die "python3 is required"
CODEX_CONFIG_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_CONFIG_DIR")"
MANIFEST_FILE="$CODEX_CONFIG_DIR/humanize-native-install.json"

if [[ -f "$MANIFEST_FILE" ]]; then
    MANIFEST_VALUES="$(python3 - "$MANIFEST_FILE" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"manifest_error\t{exc}")
    raise SystemExit(0)
for key in ("skills_dir", "agents_dir", "command_bin_dir"):
    value = data.get(key)
    if isinstance(value, str):
        print(f"{key}\t{value}")
PY
)"
    if printf '%s\n' "$MANIFEST_VALUES" | grep -q '^manifest_error'; then
        die "cannot safely parse $MANIFEST_FILE"
    fi
    if [[ "$SKILLS_EXPLICIT" != "true" ]]; then
        value="$(printf '%s\n' "$MANIFEST_VALUES" | sed -n 's/^skills_dir[[:space:]]//p' | head -1)"
        [[ -z "$value" ]] || CODEX_SKILLS_DIR="$value"
    fi
    if [[ "$AGENTS_EXPLICIT" != "true" ]]; then
        value="$(printf '%s\n' "$MANIFEST_VALUES" | sed -n 's/^agents_dir[[:space:]]//p' | head -1)"
        [[ -z "$value" ]] || CODEX_AGENTS_DIR="$value"
    fi
    if [[ "$COMMAND_BIN_EXPLICIT" != "true" ]]; then
        value="$(printf '%s\n' "$MANIFEST_VALUES" | sed -n 's/^command_bin_dir[[:space:]]//p' | head -1)"
        [[ -z "$value" ]] || COMMAND_BIN_DIR="$value"
    fi
fi

CODEX_AGENTS_DIR="${CODEX_AGENTS_DIR:-$CODEX_CONFIG_DIR/agents}"
CODEX_SKILLS_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_SKILLS_DIR")"
CODEX_AGENTS_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_AGENTS_DIR")"
COMMAND_BIN_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$COMMAND_BIN_DIR")"
LEGACY_SKILLS_DIR="$CODEX_CONFIG_DIR/skills"

remove_skill() {
    root="$1"
    name="$2"
    path="$root/$name"
    [[ -d "$path" ]] || return 0
    marker="$path/.humanize-native-managed"
    skill_file="$path/SKILL.md"
    if [[ ! -f "$marker" ]] && ! grep -qE "^name:[[:space:]]*$name[[:space:]]*$" "$skill_file" 2>/dev/null; then
        log "preserved unrecognized directory $path"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN remove skill $path"
    else
        rm -rf "$path"
        log "removed skill $path"
    fi
}

remove_agent() {
    filename="$1"
    expected_name="$2"
    path="$CODEX_AGENTS_DIR/$filename"
    [[ -f "$path" ]] || return 0
    if ! grep -qE "^name[[:space:]]*=[[:space:]]*\"$expected_name\"" "$path" 2>/dev/null; then
        log "preserved unrecognized agent file $path"
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN remove agent $path"
    else
        rm -f "$path"
        log "removed agent $path"
    fi
}

for skill in humanize humanize-rlcr humanize-consult humanize-gen-plan humanize-refine-plan; do
    remove_skill "$CODEX_SKILLS_DIR" "$skill"
done

if [[ "$LEGACY_SKILLS_DIR" != "$CODEX_SKILLS_DIR" ]]; then
    for skill in humanize humanize-rlcr humanize-consult humanize-gen-plan humanize-refine-plan; do
        remove_skill "$LEGACY_SKILLS_DIR" "$skill"
    done
fi

remove_agent humanize-worker.toml humanize_worker
remove_agent humanize-implementation-reviewer.toml humanize_implementation_reviewer
remove_agent humanize-code-reviewer.toml humanize_code_reviewer
remove_agent humanize-researcher.toml humanize_researcher

HOOK_ARGS=(--codex-config-dir "$CODEX_CONFIG_DIR")
[[ "$DRY_RUN" == "true" ]] && HOOK_ARGS+=(--dry-run)
"$SCRIPT_DIR/remove-codex-hooks.sh" "${HOOK_ARGS[@]}"

shim="$COMMAND_BIN_DIR/bitlesson-selector"
legacy_target="$LEGACY_SKILLS_DIR/humanize/scripts/bitlesson-select.sh"
if [[ -f "$shim" ]] && grep -qF -- "$legacy_target" "$shim" 2>/dev/null; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN remove legacy Codex shim $shim"
    else
        rm -f "$shim"
        log "removed legacy Codex shim $shim"
    fi
fi

if [[ -f "$MANIFEST_FILE" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN remove manifest $MANIFEST_FILE"
    else
        rm -f "$MANIFEST_FILE"
        log "removed manifest $MANIFEST_FILE"
    fi
fi

log "Codex-native Humanize uninstall complete"
