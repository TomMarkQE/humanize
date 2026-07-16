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

payload_text = b"".join(
    subprocess.check_output(["git", "show", f"{source_commit}:{part}"])
    for part in parts
).decode("utf-8")
prefix = '{"schema_version":1,"files":['
if not payload_text.startswith(prefix):
    raise SystemExit("unexpected payload prefix")

items = []
decoder = json.JSONDecoder()
pos = len(prefix)
while True:
    while pos < len(payload_text) and payload_text[pos] in " \t\r\n,":
        pos += 1
    if pos >= len(payload_text) or payload_text[pos] == "]":
        break
    try:
        item, end = decoder.raw_decode(payload_text, pos)
    except json.JSONDecodeError as exc:
        print(
            "partial_payload_stop="
            f"{exc.msg};position={exc.pos};recovered={len(items)};"
            f"last_path={items[-1]['path'] if items else 'none'}"
        )
        break
    if not isinstance(item, dict) or not {"path", "content"}.issubset(item):
        raise SystemExit(f"invalid payload item at position {pos}")
    items.append(item)
    pos = end

if len(items) < 18:
    raise SystemExit(f"too few complete payload files recovered: {len(items)}")

for item in items:
    relative = pathlib.PurePosixPath(item["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise SystemExit(f"unsafe payload path: {relative}")
    target = (root / pathlib.Path(*relative.parts)).resolve()
    if root not in target.parents and target != root:
        raise SystemExit(f"payload escaped repository: {relative}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(item["content"], encoding="utf-8", newline="\n")
    os.chmod(target, item.get("mode", 0o644))

for temporary in (
    root / ".github/workflows/restore-native-candidate.yml",
    root / ".github/restore-native-candidate.sh",
):
    if temporary.exists():
        temporary.unlink()

print("recovered_payload_paths=" + ",".join(item["path"] for item in items))
PY

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git diff --cached --quiet && exit 0
git commit -m "Restore native Codex implementation candidate"
git push origin HEAD:agent/runtime-selected-native-subagents
