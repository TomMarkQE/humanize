#!/usr/bin/env bash
# Unified installer: Kimi keeps the legacy provider bundle; Codex uses native agents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="kimi"
KIMI_SKILLS_DIR="${HOME}/.config/agents/skills"
CODEX_SKILLS_DIR="${HUMANIZE_CODEX_SKILLS_DIR:-${HOME}/.agents/skills}"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_AGENTS_DIR=""
COMMAND_BIN_DIR="${HUMANIZE_COMMAND_BIN_DIR:-${HOME}/.local/bin}"
LEGACY_SKILLS_DIR=""
DRY_RUN=false
SKILLS_SOURCE_ROOT=""
RUNTIME_SOURCE_ROOT=""

SKILL_NAMES=(
    "humanize"
    "humanize-gen-plan"
    "humanize-refine-plan"
    "humanize-rlcr"
)

usage() {
    cat <<'USAGE'
Install Humanize skills for Kimi, Codex, or both.

Usage: scripts/install-skill.sh [options]

Options:
  --target MODE           kimi|codex|both (default: kimi)
  --repo-root PATH        Humanize source checkout
  --skills-dir PATH       Compatibility alias for the selected target skill directory
  --kimi-skills-dir PATH  Kimi skills directory (default: ~/.config/agents/skills)
  --codex-skills-dir PATH Codex skills directory (default: ~/.agents/skills)
  --codex-config-dir PATH Codex config directory (default: ${CODEX_HOME:-~/.codex})
  --codex-agents-dir PATH Codex custom agent directory (default: <codex-config-dir>/agents)
  --command-bin-dir PATH  Helper shim directory for Kimi and legacy cleanup
  --dry-run               Print changes without writing
  -h, --help              Show this help

Codex installs are native-agent installs. They do not install a Stop hook or run nested Codex CLI reviewers.
USAGE
}

log() {
    printf '[install-skills] %s\n' "$*"
}

die() {
    printf '[install-skills] Error: %s\n' "$*" >&2
    exit 1
}


resolve_source_layout() {
    candidate="$1"
    if [[ -d "$candidate/skills" && -d "$candidate/scripts" && -d "$candidate/hooks" ]]; then
        SKILLS_SOURCE_ROOT="$candidate/skills"
        RUNTIME_SOURCE_ROOT="$candidate"
        return 0
    fi

    # Installed legacy runtime layout: <skills-dir>/humanize/scripts/install-skill.sh
    if [[ -d "$candidate/scripts" && -d "$candidate/hooks" && -d "$candidate/prompt-template" ]]; then
        parent="$(cd "$candidate/.." && pwd)"
        if [[ -f "$parent/humanize/SKILL.md" && -f "$parent/humanize-rlcr/SKILL.md" ]]; then
            SKILLS_SOURCE_ROOT="$parent"
            RUNTIME_SOURCE_ROOT="$candidate"
            return 0
        fi
    fi
    die "could not resolve Humanize source layout from: $candidate"
}

sync_dir() {
    src="$1"
    dst="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN sync $src -> $dst"
        return 0
    fi
    parent="$(dirname "$dst")"
    mkdir -p "$parent"
    staging="$(mktemp -d "$parent/.humanize-sync.XXXXXX")"
    if ! cp -R "$src/." "$staging/"; then
        rm -rf "$staging"
        die "failed to copy $src"
    fi
    rm -rf "$dst"
    mv "$staging" "$dst"
}

install_kimi() {
    for skill in "${SKILL_NAMES[@]}"; do
        [[ -f "$SKILLS_SOURCE_ROOT/$skill/SKILL.md" ]] || die "missing skill source: $skill"
        sync_dir "$SKILLS_SOURCE_ROOT/$skill" "$KIMI_SKILLS_DIR/$skill"
    done

    runtime_root="$KIMI_SKILLS_DIR/humanize"
    for component in scripts hooks prompt-template templates config agents; do
        [[ -d "$RUNTIME_SOURCE_ROOT/$component" ]] || die "missing runtime component: $component"
        sync_dir "$RUNTIME_SOURCE_ROOT/$component" "$runtime_root/$component"
    done

    if [[ "$DRY_RUN" != "true" ]]; then
        python3 - "$runtime_root" \
            "$KIMI_SKILLS_DIR/humanize/SKILL.md" \
            "$KIMI_SKILLS_DIR/humanize-gen-plan/SKILL.md" \
            "$KIMI_SKILLS_DIR/humanize-refine-plan/SKILL.md" \
            "$KIMI_SKILLS_DIR/humanize-rlcr/SKILL.md" <<'PY'
import os
import pathlib
import sys
import tempfile

runtime_root = sys.argv[1]
for raw in sys.argv[2:]:
    path = pathlib.Path(raw)
    text = path.read_text(encoding="utf-8").replace("{{HUMANIZE_RUNTIME_ROOT}}", runtime_root)
    lines = text.splitlines()
    output = []
    in_frontmatter = False
    frontmatter_done = False
    for line in lines:
        if line.strip() == "---" and not frontmatter_done:
            in_frontmatter = not in_frontmatter
            output.append(line)
            if not in_frontmatter:
                frontmatter_done = True
            continue
        if in_frontmatter and any(
            line.startswith(prefix)
            for prefix in ("user-invocable:", "disable-model-invocation:", "hide-from-slash-command-tool:")
        ):
            continue
        output.append(line)
    fd, temp_name = tempfile.mkstemp(prefix=".SKILL.md.", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(output) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)
PY
    fi

    shim="$COMMAND_BIN_DIR/bitlesson-selector"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN install Kimi bitlesson-selector shim -> $shim"
    else
        mkdir -p "$COMMAND_BIN_DIR"
        escaped="$(printf '%s' "$runtime_root" | sed "s/'/'\\\\''/g")"
        cat > "$shim" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec '$escaped/scripts/bitlesson-select.sh' "\$@"
EOF
        chmod +x "$shim"
    fi
    log "installed Kimi skills into $KIMI_SKILLS_DIR"
}

install_codex() {
    args=(
        --repo-root "$REPO_ROOT"
        --codex-skills-dir "$CODEX_SKILLS_DIR"
        --codex-config-dir "$CODEX_CONFIG_DIR"
        --command-bin-dir "$COMMAND_BIN_DIR"
    )
    [[ -z "$CODEX_AGENTS_DIR" ]] || args+=(--codex-agents-dir "$CODEX_AGENTS_DIR")
    [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
    "$REPO_ROOT/scripts/install-codex-native.sh" "${args[@]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            [[ -n "${2:-}" ]] || die "--target requires a value"
            case "$2" in
                kimi|codex|both) TARGET="$2" ;;
                *) die "--target must be one of: kimi, codex, both" ;;
            esac
            shift 2
            ;;
        --repo-root)
            [[ -n "${2:-}" ]] || die "--repo-root requires a value"
            REPO_ROOT="$2"
            shift 2
            ;;
        --skills-dir)
            [[ -n "${2:-}" ]] || die "--skills-dir requires a value"
            LEGACY_SKILLS_DIR="$2"
            shift 2
            ;;
        --kimi-skills-dir)
            [[ -n "${2:-}" ]] || die "--kimi-skills-dir requires a value"
            KIMI_SKILLS_DIR="$2"
            shift 2
            ;;
        --codex-skills-dir)
            [[ -n "${2:-}" ]] || die "--codex-skills-dir requires a value"
            CODEX_SKILLS_DIR="$2"
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
            shift 2
            ;;
        --command-bin-dir)
            [[ -n "${2:-}" ]] || die "--command-bin-dir requires a value"
            COMMAND_BIN_DIR="$2"
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

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
resolve_source_layout "$REPO_ROOT"

if [[ -n "$LEGACY_SKILLS_DIR" ]]; then
    case "$TARGET" in
        kimi) KIMI_SKILLS_DIR="$LEGACY_SKILLS_DIR" ;;
        codex) CODEX_SKILLS_DIR="$LEGACY_SKILLS_DIR" ;;
        both) die "--skills-dir cannot be used with --target both; use separate --kimi-skills-dir and --codex-skills-dir" ;;
    esac
fi

if [[ "$TARGET" == "both" ]]; then
    normalized_kimi="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$KIMI_SKILLS_DIR")"
    normalized_codex="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_SKILLS_DIR")"
    if [[ "$normalized_kimi" == "$normalized_codex" ]]; then
        die "Kimi and Codex skill directories must be different for --target both"
    fi
fi

case "$TARGET" in
    kimi)
        install_kimi
        ;;
    codex)
        install_codex
        ;;
    both)
        install_kimi
        install_codex
        ;;
esac
