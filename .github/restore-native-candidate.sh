#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
import json
import os
import pathlib
import subprocess

root = pathlib.Path.cwd().resolve()
source_commit = "803757b49564b71fe3eda94644762afa7650f7cb"
parts = [
    ".humanize-native-json.part-00",
    ".humanize-native-json.part-01",
    ".humanize-native-json.part-02",
    ".humanize-native-json.part-03",
    ".humanize-native-json.part-04",
    ".humanize-native-json.part-05a",
    ".humanize-native-json.part-05b",
    ".humanize-native-json.part-06",
    ".humanize-native-json.part-07",
    ".humanize-native-json.part-08",
    ".humanize-native-json.part-09",
    ".humanize-native-json.part-10",
    ".humanize-native-json.part-11",
]

payload_bytes = b"".join(
    subprocess.check_output(["git", "show", f"{source_commit}:{part}"])
    for part in parts
)
print(f"payload_bytes={len(payload_bytes)}")
payload = json.loads(payload_bytes.decode("utf-8"))
if payload.get("schema_version") != 1:
    raise SystemExit("unsupported payload schema")

items = payload.get("files")
if not isinstance(items, list) or not items:
    raise SystemExit("payload contains no files")

desired_paths = set()
for item in items:
    relative = pathlib.PurePosixPath(item["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit(f"unsafe payload path: {relative}")
    desired_paths.add(relative.as_posix())

tracked = subprocess.check_output(["git", "ls-files", "-z"]).decode("utf-8").split("\0")
for tracked_path in tracked:
    if not tracked_path:
        continue
    if tracked_path not in desired_paths:
        target = root / tracked_path
        if target.is_file() or target.is_symlink():
            target.unlink()

for item in items:
    relative = pathlib.PurePosixPath(item["path"])
    target = (root / pathlib.Path(*relative.parts)).resolve()
    if root not in target.parents and target != root:
        raise SystemExit(f"payload escaped repository: {relative}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(item["content"], encoding="utf-8", newline="\n")
    os.chmod(target, item.get("mode", 0o644))

print(f"payload_files={len(items)}")
PY

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git diff --cached --quiet && exit 0
git commit -m "Restore native Codex implementation candidate"
git push origin HEAD:agent/runtime-selected-native-subagents
