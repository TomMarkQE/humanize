#!/usr/bin/env bash
# Remove only legacy Humanize-managed Codex Stop hooks. Preserve unrelated hooks.
set -euo pipefail

CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
DRY_RUN="false"

usage() {
    cat <<'EOF'
Usage: scripts/remove-codex-hooks.sh [options]

Options:
  --codex-config-dir PATH  Codex config directory (default: ${CODEX_HOME:-~/.codex})
  --dry-run                Report the migration without writing
  -h, --help               Show help
EOF
}

log() { printf '[remove-codex-hooks] %s\n' "$*"; }
die() { printf '[remove-codex-hooks] Error: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
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
        *)
            die "unknown option: $1"
            ;;
    esac
done

HOOKS_FILE="$CODEX_CONFIG_DIR/hooks.json"
if [[ ! -e "$HOOKS_FILE" ]]; then
    log "no hooks.json found; nothing to migrate"
    exit 0
fi
[[ -f "$HOOKS_FILE" ]] || die "hooks path is not a regular file: $HOOKS_FILE"
command -v python3 >/dev/null 2>&1 || die "python3 is required to migrate hooks.json"

if [[ "$DRY_RUN" == "true" ]]; then
    python3 - "$HOOKS_FILE" <<'PY'
import json
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
pattern = re.compile(r"(^|/)hooks/(loop-codex-stop-hook\.sh|pr-loop-stop-hook\.sh)(['\"\s]|$)")
count = 0
for group in data.get("hooks", {}).get("Stop", []) or []:
    if not isinstance(group, dict):
        continue
    for hook in group.get("hooks", []) or []:
        if isinstance(hook, dict) and isinstance(hook.get("command"), str) and pattern.search(hook["command"]):
            count += 1
print(count)
PY
    log "DRY-RUN would remove the managed Humanize Stop hook count shown above"
    exit 0
fi

python3 - "$HOOKS_FILE" <<'PY'
import json
import os
import pathlib
import re
import tempfile
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    raise SystemExit(f"malformed hooks.json: {exc}")
if not isinstance(data, dict):
    raise SystemExit("hooks.json must contain a JSON object")

hooks = data.get("hooks")
if hooks is None:
    print("REMOVED=0")
    raise SystemExit(0)
if not isinstance(hooks, dict):
    raise SystemExit("hooks.json field 'hooks' must be an object")

stop_groups = hooks.get("Stop", [])
if stop_groups is None:
    stop_groups = []
if not isinstance(stop_groups, list):
    raise SystemExit("hooks.json field 'hooks.Stop' must be an array")

pattern = re.compile(r"(^|/)hooks/(loop-codex-stop-hook\.sh|pr-loop-stop-hook\.sh)(['\"\s]|$)")
removed = 0
new_groups = []
for group in stop_groups:
    if not isinstance(group, dict):
        new_groups.append(group)
        continue
    entries = group.get("hooks")
    if not isinstance(entries, list):
        new_groups.append(group)
        continue
    kept = []
    for hook in entries:
        command = hook.get("command") if isinstance(hook, dict) else None
        if isinstance(command, str) and pattern.search(command):
            removed += 1
        else:
            kept.append(hook)
    if kept:
        replacement = dict(group)
        replacement["hooks"] = kept
        new_groups.append(replacement)

if removed:
    hooks["Stop"] = new_groups
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(data, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_name, path)
    finally:
        if os.path.exists(tmp_name):
            os.unlink(tmp_name)
print(f"REMOVED={removed}")
PY

log "legacy Humanize Stop-hook migration complete"
