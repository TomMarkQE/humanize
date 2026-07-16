#!/usr/bin/env bash
# Remove only legacy Humanize-managed Codex Stop hooks while preserving user hooks.
set -euo pipefail

CODEX_CONFIG_DIR="${CODEX_HOME:-${HOME}/.codex}"
DRY_RUN=false

usage() {
    cat <<'USAGE'
Remove legacy Humanize Codex hooks without changing unrelated hooks.

Usage: scripts/remove-codex-hooks.sh [options]

Options:
  --codex-config-dir PATH  Codex config directory (default: ${CODEX_HOME:-~/.codex})
  --dry-run                Report what would be removed without writing
  -h, --help               Show this help
USAGE
}

die() {
    printf '[remove-codex-hooks] Error: %s\n' "$*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --codex-config-dir)
            [[ -n "${2:-}" ]] || die "--codex-config-dir requires a value"
            CODEX_CONFIG_DIR="$2"
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
HOOKS_FILE="$CODEX_CONFIG_DIR/hooks.json"

python3 - "$HOOKS_FILE" "$DRY_RUN" <<'PY'
import json
import os
import pathlib
import re
import sys
import tempfile

hooks_file = pathlib.Path(sys.argv[1]).expanduser()
dry_run = sys.argv[2].lower() == "true"
managed = re.compile(r"(^|[/\\])hooks[/\\](loop-codex-stop-hook\.sh|pr-loop-stop-hook\.sh)(?:['\"\s]|$)")

if not hooks_file.exists():
    print("[remove-codex-hooks] no hooks.json found; nothing to remove")
    raise SystemExit(0)

try:
    data = json.loads(hooks_file.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    print(f"[remove-codex-hooks] Error: cannot safely parse {hooks_file}: {exc}", file=sys.stderr)
    raise SystemExit(2)

if not isinstance(data, dict):
    print(f"[remove-codex-hooks] Error: {hooks_file} must contain a JSON object", file=sys.stderr)
    raise SystemExit(2)

hooks = data.get("hooks")
if hooks is None:
    print("[remove-codex-hooks] hooks.json has no hooks object; nothing to remove")
    raise SystemExit(0)
if not isinstance(hooks, dict):
    print(f"[remove-codex-hooks] Error: {hooks_file} has a non-object hooks value", file=sys.stderr)
    raise SystemExit(2)

stop_groups = hooks.get("Stop", [])
if stop_groups is None:
    stop_groups = []
if not isinstance(stop_groups, list):
    print(f"[remove-codex-hooks] Error: {hooks_file} has a non-array Stop value", file=sys.stderr)
    raise SystemExit(2)

removed = 0
filtered_groups = []
for group in stop_groups:
    if not isinstance(group, dict):
        filtered_groups.append(group)
        continue
    group_hooks = group.get("hooks")
    if not isinstance(group_hooks, list):
        filtered_groups.append(group)
        continue
    kept = []
    for hook in group_hooks:
        if isinstance(hook, dict):
            command = hook.get("command")
            if isinstance(command, str) and managed.search(command):
                removed += 1
                continue
        kept.append(hook)
    if kept:
        new_group = dict(group)
        new_group["hooks"] = kept
        filtered_groups.append(new_group)

if removed == 0:
    print("[remove-codex-hooks] no legacy Humanize hooks found")
    raise SystemExit(0)

print(f"[remove-codex-hooks] {'would remove' if dry_run else 'removed'} {removed} legacy Humanize hook(s)")
if dry_run:
    raise SystemExit(0)

if filtered_groups:
    hooks["Stop"] = filtered_groups
else:
    hooks.pop("Stop", None)

data["hooks"] = hooks
hooks_file.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix=".hooks.json.", dir=str(hooks_file.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_name, hooks_file)
except Exception:
    try:
        os.unlink(temp_name)
    except OSError:
        pass
    raise
PY
