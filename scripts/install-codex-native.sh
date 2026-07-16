#!/usr/bin/env bash
# Install the Codex-native Humanize skills and custom agents.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
CODEX_SKILLS_DIR="${HUMANIZE_CODEX_SKILLS_DIR:-${HOME}/.agents/skills}"
CODEX_AGENTS_DIR=""
COMMAND_BIN_DIR="${HUMANIZE_COMMAND_BIN_DIR:-${HOME}/.local/bin}"
DRY_RUN=false

usage() {
    cat <<'USAGE'
Install Humanize's Codex-native skills and custom agents.

Usage: scripts/install-codex-native.sh [options]

Options:
  --repo-root PATH         Humanize source checkout (default: repository root)
  --codex-skills-dir PATH  Codex user skills directory (default: ~/.agents/skills)
  --codex-config-dir PATH  Codex config directory (default: ${CODEX_HOME:-~/.codex})
  --codex-agents-dir PATH  Custom agent directory (default: <codex-config-dir>/agents)
  --command-bin-dir PATH   Legacy shim directory to clean during migration
  --dry-run                Print changes without writing
  -h, --help               Show this help
USAGE
}

log() {
    printf '[install-codex-native] %s\n' "$*"
}

die() {
    printf '[install-codex-native] Error: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root)
            [[ -n "${2:-}" ]] || die "--repo-root requires a value"
            REPO_ROOT="$2"
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
CODEX_AGENTS_DIR="${CODEX_AGENTS_DIR:-$CODEX_CONFIG_DIR/agents}"

command -v python3 >/dev/null 2>&1 || die "python3 is required"
CODEX_CONFIG_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_CONFIG_DIR")"
CODEX_SKILLS_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_SKILLS_DIR")"
CODEX_AGENTS_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$CODEX_AGENTS_DIR")"
COMMAND_BIN_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).expanduser().resolve())' "$COMMAND_BIN_DIR")"
LEGACY_SKILLS_DIR="$CODEX_CONFIG_DIR/skills"
MANIFEST_FILE="$CODEX_CONFIG_DIR/humanize-native-install.json"

NATIVE_SKILLS_ROOT="$REPO_ROOT/codex/skills"
SHARED_SKILLS_ROOT="$REPO_ROOT/skills"
NATIVE_AGENTS_ROOT="$REPO_ROOT/codex/agents"

for path in \
    "$NATIVE_SKILLS_ROOT/humanize/SKILL.md" \
    "$NATIVE_SKILLS_ROOT/humanize-rlcr/SKILL.md" \
    "$NATIVE_SKILLS_ROOT/humanize-consult/SKILL.md" \
    "$SHARED_SKILLS_ROOT/humanize-gen-plan/SKILL.md" \
    "$SHARED_SKILLS_ROOT/humanize-refine-plan/SKILL.md" \
    "$REPO_ROOT/scripts/native-rlcr.py" \
    "$REPO_ROOT/scripts/remove-codex-hooks.sh"; do
    [[ -f "$path" ]] || die "required source asset missing: $path"
done

for agent in humanize-worker humanize-implementation-reviewer humanize-code-reviewer humanize-researcher; do
    [[ -f "$NATIVE_AGENTS_ROOT/$agent.toml" ]] || die "required custom agent missing: $agent.toml"
done

sync_dir() {
    src="$1"
    dst="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN sync $src -> $dst"
        return 0
    fi
    parent="$(dirname "$dst")"
    mkdir -p "$parent"
    staging="$(mktemp -d "$parent/.humanize-native-sync.XXXXXX")"
    if ! cp -R "$src/." "$staging/"; then
        rm -rf "$staging"
        die "failed to copy $src"
    fi
    rm -rf "$dst"
    mv "$staging" "$dst"
}

copy_file() {
    src="$1"
    dst="$2"
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN copy $src -> $dst"
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    temp="$dst.tmp.$$"
    cp "$src" "$temp"
    chmod --reference="$src" "$temp" 2>/dev/null || true
    mv "$temp" "$dst"
}

remove_known_skill_dir() {
    root="$1"
    name="$2"
    path="$root/$name"
    [[ -d "$path" ]] || return 0
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN remove stale skill $path"
    else
        rm -rf "$path"
        log "removed stale skill $path"
    fi
}

remove_legacy_shim() {
    shim="$COMMAND_BIN_DIR/bitlesson-selector"
    [[ -f "$shim" ]] || return 0
    legacy_target="$LEGACY_SKILLS_DIR/humanize/scripts/bitlesson-select.sh"
    # Remove only a shim that points at the former Codex runtime.  Kimi uses a
    # shim with the same filename but a different runtime root and must survive
    # a Codex install or upgrade.
    if grep -qF -- "$legacy_target" "$shim" 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY-RUN remove legacy Codex shim $shim"
        else
            rm -f "$shim"
            log "removed legacy Codex shim $shim"
        fi
    fi
}

log "source: $REPO_ROOT"
log "skills: $CODEX_SKILLS_DIR"
log "agents: $CODEX_AGENTS_DIR"
log "config: $CODEX_CONFIG_DIR"

# Remove old managed Stop hooks first.  This preserves all unrelated hook groups.
HOOK_ARGS=(--codex-config-dir "$CODEX_CONFIG_DIR")
[[ "$DRY_RUN" == "true" ]] && HOOK_ARGS+=(--dry-run)
"$REPO_ROOT/scripts/remove-codex-hooks.sh" "${HOOK_ARGS[@]}"

# Migrate away from the former ~/.codex/skills location to the current user skill location.
if [[ "$LEGACY_SKILLS_DIR" != "$CODEX_SKILLS_DIR" ]]; then
    for skill in humanize humanize-gen-plan humanize-refine-plan humanize-rlcr humanize-consult; do
        remove_known_skill_dir "$LEGACY_SKILLS_DIR" "$skill"
    done
fi
remove_legacy_shim

# Install Codex-specific orchestration skills and shared plan skills.
sync_dir "$NATIVE_SKILLS_ROOT/humanize" "$CODEX_SKILLS_DIR/humanize"
sync_dir "$NATIVE_SKILLS_ROOT/humanize-rlcr" "$CODEX_SKILLS_DIR/humanize-rlcr"
sync_dir "$NATIVE_SKILLS_ROOT/humanize-consult" "$CODEX_SKILLS_DIR/humanize-consult"
sync_dir "$SHARED_SKILLS_ROOT/humanize-gen-plan" "$CODEX_SKILLS_DIR/humanize-gen-plan"
sync_dir "$SHARED_SKILLS_ROOT/humanize-refine-plan" "$CODEX_SKILLS_DIR/humanize-refine-plan"

# Install only deterministic runtime components required by Codex-native skills.
if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN install deterministic runtime under $CODEX_SKILLS_DIR/humanize"
else
    mkdir -p "$CODEX_SKILLS_DIR/humanize/scripts/lib"
fi
copy_file "$REPO_ROOT/scripts/native-rlcr.py" "$CODEX_SKILLS_DIR/humanize/scripts/native-rlcr.py"
copy_file "$REPO_ROOT/scripts/validate-gen-plan-io.sh" "$CODEX_SKILLS_DIR/humanize/scripts/validate-gen-plan-io.sh"
copy_file "$REPO_ROOT/scripts/validate-refine-plan-io.sh" "$CODEX_SKILLS_DIR/humanize/scripts/validate-refine-plan-io.sh"
copy_file "$REPO_ROOT/scripts/lib/config-loader.sh" "$CODEX_SKILLS_DIR/humanize/scripts/lib/config-loader.sh"
sync_dir "$REPO_ROOT/prompt-template" "$CODEX_SKILLS_DIR/humanize/prompt-template"
sync_dir "$REPO_ROOT/config" "$CODEX_SKILLS_DIR/humanize/config"

# Replace all previously managed custom agent files atomically and remove stale variants.
for name in humanize-worker humanize-implementation-reviewer humanize-code-reviewer humanize-researcher; do
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY-RUN install agent $name.toml -> $CODEX_AGENTS_DIR"
    else
        mkdir -p "$CODEX_AGENTS_DIR"
        rm -f "$CODEX_AGENTS_DIR/$name.toml"
        copy_file "$NATIVE_AGENTS_ROOT/$name.toml" "$CODEX_AGENTS_DIR/$name.toml"
    fi
done

if [[ "$DRY_RUN" != "true" ]]; then
    python3 - "$CODEX_SKILLS_DIR/humanize" \
        "$CODEX_SKILLS_DIR/humanize/SKILL.md" \
        "$CODEX_SKILLS_DIR/humanize-rlcr/SKILL.md" \
        "$CODEX_SKILLS_DIR/humanize-consult/SKILL.md" \
        "$CODEX_SKILLS_DIR/humanize-gen-plan/SKILL.md" \
        "$CODEX_SKILLS_DIR/humanize-refine-plan/SKILL.md" <<'PY'
import os
import pathlib
import sys
import tempfile

runtime_root = sys.argv[1]
for raw_path in sys.argv[2:]:
    path = pathlib.Path(raw_path)
    text = path.read_text(encoding="utf-8").replace("{{HUMANIZE_RUNTIME_ROOT}}", runtime_root)
    lines = text.splitlines()
    output = []
    in_frontmatter = False
    frontmatter_seen = False
    for line in lines:
        if line.strip() == "---" and not frontmatter_seen:
            in_frontmatter = not in_frontmatter
            output.append(line)
            if not in_frontmatter:
                frontmatter_seen = True
            continue
        if in_frontmatter and any(
            line.startswith(prefix)
            for prefix in ("type:", "user-invocable:", "disable-model-invocation:", "hide-from-slash-command-tool:")
        ):
            continue
        output.append(line)
    content = "\n".join(output) + "\n"
    fd, temp_name = tempfile.mkstemp(prefix=".SKILL.md.", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, path)
    (path.parent / ".humanize-native-managed").write_text("managed by Humanize Codex native installer\n", encoding="utf-8")
PY
    chmod +x "$CODEX_SKILLS_DIR/humanize/scripts/native-rlcr.py" \
        "$CODEX_SKILLS_DIR/humanize/scripts/validate-gen-plan-io.sh" \
        "$CODEX_SKILLS_DIR/humanize/scripts/validate-refine-plan-io.sh"

    VERSION="$(python3 - "$REPO_ROOT/.claude-plugin/plugin.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
try:
    print(json.loads(path.read_text(encoding="utf-8")).get("version", "unknown"))
except Exception:
    print("unknown")
PY
)"
    mkdir -p "$CODEX_CONFIG_DIR"
    python3 - "$MANIFEST_FILE" "$VERSION" "$CODEX_SKILLS_DIR" "$CODEX_AGENTS_DIR" "$LEGACY_SKILLS_DIR" "$COMMAND_BIN_DIR" <<'PY'
import json
import os
import pathlib
import sys
import tempfile
from datetime import datetime, timezone

path = pathlib.Path(sys.argv[1])
payload = {
    "schema_version": 1,
    "mode": "codex-native",
    "version": sys.argv[2],
    "skills_dir": sys.argv[3],
    "agents_dir": sys.argv[4],
    "legacy_skills_dir": sys.argv[5],
    "command_bin_dir": sys.argv[6],
    "skills": ["humanize", "humanize-rlcr", "humanize-consult", "humanize-gen-plan", "humanize-refine-plan"],
    "agents": ["humanize-worker.toml", "humanize-implementation-reviewer.toml", "humanize-code-reviewer.toml", "humanize-researcher.toml"],
    "installed_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
}
path.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix=".humanize-native-install.", dir=str(path.parent))
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.replace(temp_name, path)
PY
fi

cat <<EOF

Humanize Codex-native installation complete.
  Skills:   $CODEX_SKILLS_DIR
  Agents:   $CODEX_AGENTS_DIR
  Manifest: $MANIFEST_FILE

No Codex Stop hook was installed. Legacy Humanize Codex hooks and duplicate skill copies were removed.
EOF
