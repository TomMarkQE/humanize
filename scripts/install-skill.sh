#!/usr/bin/env bash
# Install/upgrade Humanize skills for Kimi and/or Codex.
# Codex receives provider-specific native-subagent skills; Kimi retains legacy skills.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIMI_SKILLS_SOURCE_ROOT=""
CODEX_SKILLS_SOURCE_ROOT=""
RUNTIME_SOURCE_ROOT=""
TARGET="kimi"
KIMI_SKILLS_DIR="${HOME}/.config/agents/skills"
CODEX_SKILLS_DIR="${CODEX_HOME:-${HOME}/.codex}/skills"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
HUMANIZE_USER_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/humanize"
COMMAND_BIN_DIR="${HUMANIZE_COMMAND_BIN_DIR:-${HOME}/.local/bin}"
LEGACY_SKILLS_DIR=""
DRY_RUN="false"
SOURCE_LAYOUT="checkout"

SKILL_NAMES=(humanize humanize-gen-plan humanize-refine-plan humanize-rlcr)

usage() {
    cat <<'EOF'
Install Humanize skills for Kimi and/or Codex.

Usage:
  scripts/install-skill.sh [options]

Options:
  --target MODE           kimi|codex|both (default: kimi)
  --repo-root PATH        Humanize repo root (default: auto-detect)
  --skills-dir PATH       Legacy alias for the selected target skills directory
  --kimi-skills-dir PATH  Kimi skills directory (default: ~/.config/agents/skills)
  --codex-skills-dir PATH Codex skills directory (default: ${CODEX_HOME:-~/.codex}/skills)
  --codex-config-dir PATH Codex config directory used to remove legacy Humanize hooks
  --command-bin-dir PATH  Install helper command shims here (default: ~/.local/bin)
  --dry-run               Print actions without writing
  -h, --help              Show help
EOF
}

log() { printf '[install-skills] %s\n' "$*"; }
die() { printf '[install-skills] Error: %s\n' "$*" >&2; exit 1; }

resolve_source_layout() {
    local candidate_root="$1"
    local skills_root

    if [[ -d "$candidate_root/skills" ]] && [[ -d "$candidate_root/codex-skills" ]] && [[ -d "$candidate_root/scripts" ]]; then
        KIMI_SKILLS_SOURCE_ROOT="$candidate_root/skills"
        CODEX_SKILLS_SOURCE_ROOT="$candidate_root/codex-skills"
        RUNTIME_SOURCE_ROOT="$candidate_root"
        SOURCE_LAYOUT="checkout"
        return 0
    fi

    # Reinstall from an installed runtime. The adjacent skill set is already provider-specific.
    if [[ -d "$candidate_root/scripts" ]] && [[ -d "$candidate_root/prompt-template" ]]; then
        skills_root="$(cd "$candidate_root/.." && pwd)"
        if [[ -f "$skills_root/humanize/SKILL.md" ]] && [[ -f "$skills_root/humanize-rlcr/SKILL.md" ]]; then
            KIMI_SKILLS_SOURCE_ROOT="$skills_root"
            CODEX_SKILLS_SOURCE_ROOT="$skills_root"
            RUNTIME_SOURCE_ROOT="$candidate_root"
            SOURCE_LAYOUT="installed"
            return 0
        fi
    fi

    die "could not resolve Humanize source layout from: $candidate_root"
}

validate_skill_root() {
    local label="$1" root="$2" skill
    [[ -d "$root" ]] || die "$label skills source directory not found: $root"
    for skill in "${SKILL_NAMES[@]}"; do
        [[ -f "$root/$skill/SKILL.md" ]] || die "missing $root/$skill/SKILL.md"
    done
}

validate_repo() {
    [[ -n "$RUNTIME_SOURCE_ROOT" ]] || die "runtime source root is not set"
    [[ -d "$RUNTIME_SOURCE_ROOT/scripts" ]] || die "scripts directory not found under runtime source root"
    [[ -d "$RUNTIME_SOURCE_ROOT/prompt-template" ]] || die "prompt-template directory not found under runtime source root"
    [[ -d "$RUNTIME_SOURCE_ROOT/templates" ]] || die "templates directory not found under runtime source root"
    [[ -d "$RUNTIME_SOURCE_ROOT/config" ]] || die "config directory not found under runtime source root"
    [[ -d "$RUNTIME_SOURCE_ROOT/agents" ]] || die "agents directory not found under runtime source root"
    if [[ "$TARGET" == "codex" || "$TARGET" == "both" ]]; then
        [[ -f "$RUNTIME_SOURCE_ROOT/scripts/native-rlcr.py" ]] || die "native Codex runtime missing: scripts/native-rlcr.py"
        [[ -f "$RUNTIME_SOURCE_ROOT/scripts/remove-codex-hooks.sh" ]] || die "Codex hook migration helper missing"
    fi
    case "$TARGET" in
        kimi) validate_skill_root "Kimi" "$KIMI_SKILLS_SOURCE_ROOT" ;;
        codex) validate_skill_root "Codex" "$CODEX_SKILLS_SOURCE_ROOT" ;;
        both)
            [[ "$SOURCE_LAYOUT" == "checkout" ]] || die "--target both requires a source checkout with provider-specific skills"
            validate_skill_root "Kimi" "$KIMI_SKILLS_SOURCE_ROOT"
            validate_skill_root "Codex" "$CODEX_SKILLS_SOURCE_ROOT"
            ;;
    esac
}

sync_dir() {
    local src="$1" dst="$2" src_abs dst_abs
    src_abs="$(cd "$src" && pwd)"
    if [[ -d "$dst" ]]; then
        dst_abs="$(cd "$dst" && pwd)"
        if [[ "$src_abs" == "$dst_abs" ]]; then
            log "source and destination are identical; keeping $dst"
            return
        fi
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN sync $src -> $dst"
        return
    fi
    mkdir -p "$dst"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "$src/" "$dst/"
    else
        local tmp_dst
        tmp_dst="$(mktemp -d "$(dirname "$dst")/.sync_tmp.XXXXXX")"
        if cp -a "$src/." "$tmp_dst/"; then
            rm -rf "$dst"
            mv "$tmp_dst" "$dst"
        else
            rm -rf "$tmp_dst"
            die "failed to copy $src to $dst"
        fi
    fi
}

sync_one_skill() {
    local source_root="$1" skill="$2" target_dir="$3"
    sync_dir "$source_root/$skill" "$target_dir/$skill"
}

install_runtime_bundle() {
    local label="$1" target_dir="$2" runtime_root="$target_dir/humanize" component
    log "syncing [$label] runtime bundle into: $runtime_root"
    for component in scripts prompt-template templates config agents; do
        sync_dir "$RUNTIME_SOURCE_ROOT/$component" "$runtime_root/$component"
    done
    if [[ "$label" == "kimi" ]]; then
        [[ -d "$RUNTIME_SOURCE_ROOT/hooks" ]] || die "hooks directory required for Kimi runtime"
        sync_dir "$RUNTIME_SOURCE_ROOT/hooks" "$runtime_root/hooks"
    elif [[ "$DRY_RUN" != "true" ]]; then
        # Codex native orchestration does not install or ship an active hook entrypoint.
        rm -rf "$runtime_root/hooks"
    fi
}

hydrate_skill_runtime_root() {
    local target_dir="$1" runtime_root="$target_dir/humanize" skill skill_file tmp
    for skill in "${SKILL_NAMES[@]}"; do
        skill_file="$target_dir/$skill/SKILL.md"
        [[ -f "$skill_file" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN hydrate runtime root in $skill_file"
            continue
        fi
        tmp="$(mktemp)"
        _HYDRATE_RUNTIME_ROOT="$runtime_root" \
            awk '{gsub(/\{\{HUMANIZE_RUNTIME_ROOT\}\}/, ENVIRON["_HYDRATE_RUNTIME_ROOT"]); print}' "$skill_file" > "$tmp" \
            || { rm -f "$tmp"; die "failed to hydrate $skill_file"; }
        mv "$tmp" "$skill_file"
    done
}

strip_claude_specific_frontmatter() {
    local target_dir="$1" skill skill_file tmp
    for skill in "${SKILL_NAMES[@]}"; do
        skill_file="$target_dir/$skill/SKILL.md"
        [[ -f "$skill_file" ]] || continue
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN strip Claude-specific frontmatter in $skill_file"
            continue
        fi
        tmp="$(mktemp)"
        awk '
            BEGIN { in_fm = 0; fm_done = 0 }
            /^---[[:space:]]*$/ {
                if (fm_done == 0) {
                    in_fm = !in_fm
                    if (in_fm == 0) fm_done = 1
                }
                print
                next
            }
            in_fm && $0 ~ /^user-invocable:[[:space:]]*/ { next }
            in_fm && $0 ~ /^disable-model-invocation:[[:space:]]*/ { next }
            in_fm && $0 ~ /^hide-from-slash-command-tool:[[:space:]]*/ { next }
            { print }
        ' "$skill_file" > "$tmp" || { rm -f "$tmp"; die "failed to update $skill_file"; }
        mv "$tmp" "$skill_file"
    done
}

sync_target() {
    local label="$1" source_root="$2" target_dir="$3" skill
    log "target: $label"
    log "skills dir: $target_dir"
    [[ "$DRY_RUN" == "true" ]] || mkdir -p "$target_dir"
    for skill in "${SKILL_NAMES[@]}"; do
        log "syncing [$label] skill: $skill"
        sync_one_skill "$source_root" "$skill" "$target_dir"
    done
    install_runtime_bundle "$label" "$target_dir"
    hydrate_skill_runtime_root "$target_dir"
    strip_claude_specific_frontmatter "$target_dir"
}

remove_codex_legacy_hooks() {
    local cleanup="$RUNTIME_SOURCE_ROOT/scripts/remove-codex-hooks.sh" args=(--codex-config-dir "$CODEX_CONFIG_DIR")
    [[ -f "$cleanup" ]] || die "missing hook migration helper: $cleanup"
    [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
    log "removing legacy Humanize Codex Stop hooks from: $CODEX_CONFIG_DIR"
    bash "$cleanup" "${args[@]}"
}

install_codex_user_config() {
    local runtime_root="$1" install_target="$2"
    local user_config_dir="$HUMANIZE_USER_CONFIG_DIR"
    local user_config_file="$user_config_dir/config.json"
    local default_config_file="$runtime_root/config/default_config.json"
    [[ -f "$default_config_file" ]] || die "missing default config: $default_config_file"
    command -v python3 >/dev/null 2>&1 || die "python3 is required to update Humanize user config"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN seed Codex-friendly BitLesson config in $user_config_file"
        return
    fi
    mkdir -p "$user_config_dir"
    python3 - "$default_config_file" "$user_config_file" "$install_target" <<'PY'
import json
import pathlib
import sys

default_config = pathlib.Path(sys.argv[1])
user_config = pathlib.Path(sys.argv[2])
install_target = sys.argv[3]
defaults = json.loads(default_config.read_text(encoding="utf-8"))
default_codex_model = defaults.get("codex_model") or "gpt-5.5"
if user_config.exists():
    try:
        data = json.loads(user_config.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"malformed existing user config: {user_config}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"existing user config is not a JSON object: {user_config}")
else:
    data = {}
if not data.get("bitlesson_model"):
    data["bitlesson_model"] = data.get("codex_model") or default_codex_model
if install_target == "codex" and not data.get("provider_mode"):
    data["provider_mode"] = "codex-only"
user_config.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    log "ensured BitLesson uses a Codex/OpenAI model in $user_config_file"
}

install_bitlesson_selector_shim() {
    local primary_runtime_root="$1" secondary_runtime_root="${2:-}"
    local shim_path="$COMMAND_BIN_DIR/bitlesson-selector" escaped_primary escaped_secondary
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN install bitlesson-selector shim into $shim_path"
        return
    fi
    mkdir -p "$COMMAND_BIN_DIR"
    escaped_primary=$(printf '%s' "$primary_runtime_root" | sed "s/'/'\\\\''/g")
    cat > "$shim_path" <<SHIM_EOF
#!/usr/bin/env bash
set -euo pipefail
candidate_paths=(
  '${escaped_primary}/scripts/bitlesson-select.sh'
SHIM_EOF
    if [[ -n "$secondary_runtime_root" ]]; then
        escaped_secondary=$(printf '%s' "$secondary_runtime_root" | sed "s/'/'\\\\''/g")
        printf "  '%s/scripts/bitlesson-select.sh'\n" "$escaped_secondary" >> "$shim_path"
    fi
    cat >> "$shim_path" <<'EOF'
)
for candidate in "${candidate_paths[@]}"; do
    if [[ -x "$candidate" ]]; then
        exec "$candidate" "$@"
    fi
done
echo "Error: Humanize bitlesson selector runtime not found. Re-run install-skill.sh." >&2
exit 1
EOF
    chmod +x "$shim_path"
    log "installed bitlesson-selector shim into: $shim_path"
}

install_kimi_target() {
    sync_target "kimi" "$KIMI_SKILLS_SOURCE_ROOT" "$KIMI_SKILLS_DIR"
}

install_codex_target() {
    sync_target "codex" "$CODEX_SKILLS_SOURCE_ROOT" "$CODEX_SKILLS_DIR"
    install_codex_user_config "$CODEX_SKILLS_DIR/humanize" "$TARGET"
    remove_codex_legacy_hooks
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ -n "${2:-}" ]] || die "--target requires a value"
            case "$2" in kimi|codex|both) TARGET="$2" ;; *) die "--target must be one of: kimi, codex, both" ;; esac
            shift 2
            ;;
        --repo-root) [[ -n "${2:-}" ]] || die "--repo-root requires a value"; REPO_ROOT="$2"; shift 2 ;;
        --skills-dir) [[ -n "${2:-}" ]] || die "--skills-dir requires a value"; LEGACY_SKILLS_DIR="$2"; shift 2 ;;
        --kimi-skills-dir) [[ -n "${2:-}" ]] || die "--kimi-skills-dir requires a value"; KIMI_SKILLS_DIR="$2"; shift 2 ;;
        --codex-skills-dir) [[ -n "${2:-}" ]] || die "--codex-skills-dir requires a value"; CODEX_SKILLS_DIR="$2"; shift 2 ;;
        --codex-config-dir) [[ -n "${2:-}" ]] || die "--codex-config-dir requires a value"; CODEX_CONFIG_DIR="$2"; shift 2 ;;
        --command-bin-dir) [[ -n "${2:-}" ]] || die "--command-bin-dir requires a value"; COMMAND_BIN_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

resolve_source_layout "$REPO_ROOT"
validate_repo

if [[ -n "$LEGACY_SKILLS_DIR" ]]; then
    case "$TARGET" in
        kimi) KIMI_SKILLS_DIR="$LEGACY_SKILLS_DIR" ;;
        codex) CODEX_SKILLS_DIR="$LEGACY_SKILLS_DIR" ;;
        both) die "--skills-dir cannot represent two provider-specific targets; use both explicit directory options" ;;
    esac
fi

if [[ "$TARGET" == "both" ]] && [[ "$KIMI_SKILLS_DIR" == "$CODEX_SKILLS_DIR" ]]; then
    die "Kimi and Codex skills directories must differ for --target both"
fi

log "repo root: $REPO_ROOT"
log "target: $TARGET"
[[ "$TARGET" == "kimi" || "$TARGET" == "both" ]] && log "kimi skills dir: $KIMI_SKILLS_DIR"
[[ "$TARGET" == "codex" || "$TARGET" == "both" ]] && { log "codex skills dir: $CODEX_SKILLS_DIR"; log "codex config dir: $CODEX_CONFIG_DIR"; }
log "command bin dir: $COMMAND_BIN_DIR"

case "$TARGET" in
    kimi)
        install_kimi_target
        install_bitlesson_selector_shim "$KIMI_SKILLS_DIR/humanize"
        ;;
    codex)
        install_codex_target
        install_bitlesson_selector_shim "$CODEX_SKILLS_DIR/humanize" "$KIMI_SKILLS_DIR/humanize"
        ;;
    both)
        install_kimi_target
        install_codex_target
        install_bitlesson_selector_shim "$CODEX_SKILLS_DIR/humanize" "$KIMI_SKILLS_DIR/humanize"
        ;;
esac

cat <<EOF

Done.

Skills synced:
EOF
[[ "$TARGET" == "kimi" || "$TARGET" == "both" ]] && printf '  - kimi:  %s\n' "$KIMI_SKILLS_DIR"
[[ "$TARGET" == "codex" || "$TARGET" == "both" ]] && printf '  - codex: %s\n' "$CODEX_SKILLS_DIR"
cat <<EOF

Runtime root per target:
  <skills-dir>/humanize

Codex installs remove stale Humanize-managed Stop-hook entries and use native child threads.
No shell profile changes were made.
If $COMMAND_BIN_DIR is on PATH, the bitlesson-selector shim is now available there.
EOF
