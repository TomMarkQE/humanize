#!/usr/bin/env python3
"""Deterministic IO and schema validation for Codex Humanizer planning skills."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence, Tuple

GEN_REQUIRED = (
    "## Goal Description",
    "## Acceptance Criteria",
    "## Path Boundaries",
    "## Feasibility Hints and Suggestions",
    "## Dependencies and Sequence",
    "## Task Breakdown",
    "## Pending User Decisions",
    "## Implementation Notes",
)


class ValidationError(RuntimeError):
    def __init__(self, code: int, kind: str, message: str):
        super().__init__(message)
        self.code = code
        self.kind = kind


def resolve(path: str) -> pathlib.Path:
    return pathlib.Path(path).expanduser().resolve()


def require_input(path: pathlib.Path) -> str:
    if not path.is_file():
        raise ValidationError(1, "INPUT_NOT_FOUND", f"input file does not exist: {path}")
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        raise ValidationError(2, "INPUT_NOT_UTF8", f"input file must be UTF-8: {path}") from exc
    if not text.strip():
        raise ValidationError(2, "INPUT_EMPTY", f"input file is empty: {path}")
    return text


def require_new_output(path: pathlib.Path) -> None:
    if path.exists():
        raise ValidationError(4, "OUTPUT_EXISTS", f"output path already exists: {path}")
    parent = path.parent
    if not parent.is_dir():
        raise ValidationError(3, "OUTPUT_DIR_NOT_FOUND", f"output directory does not exist: {parent}")
    if not os.access(parent, os.W_OK):
        raise ValidationError(5, "OUTPUT_DIR_NOT_WRITABLE", f"output directory is not writable: {parent}")


def require_writable_output(path: pathlib.Path, input_path: pathlib.Path) -> None:
    parent = path.parent
    if not parent.is_dir():
        raise ValidationError(5, "OUTPUT_DIR_NOT_FOUND", f"output directory does not exist: {parent}")
    if not os.access(parent, os.W_OK):
        raise ValidationError(5, "OUTPUT_DIR_NOT_WRITABLE", f"output directory is not writable: {parent}")
    if path == input_path and not os.access(input_path.parent, os.W_OK):
        raise ValidationError(5, "INPUT_DIR_NOT_WRITABLE", f"input directory is not writable: {input_path.parent}")


def ensure_qa_dir(path: pathlib.Path) -> None:
    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise ValidationError(6, "QA_DIR_NOT_WRITABLE", f"cannot create QA directory: {path}: {exc}") from exc
    if not path.is_dir() or not os.access(path, os.W_OK):
        raise ValidationError(6, "QA_DIR_NOT_WRITABLE", f"QA directory is not writable: {path}")


@dataclass
class ScanResult:
    comments: List[str]
    headings: List[str]


def scan_plan(text: str) -> ScanResult:
    lines = text.splitlines()
    comments: List[str] = []
    headings: List[str] = []
    in_fence = False
    fence = ""
    in_html = False
    active_end: Optional[str] = None
    active_start: Optional[Tuple[int, int, str]] = None
    active_parts: List[str] = []

    starts = (("CMT:", "ENDCMT"), ("<cmt>", "</cmt>"), ("<comment>", "</comment>"))
    all_starts = {item[0]: item[1] for item in starts}
    all_ends = {item[1] for item in starts}

    for line_no, line in enumerate(lines, 1):
        stripped = line.lstrip()
        if not in_html and active_end is None:
            if not in_fence and (stripped.startswith("```") or stripped.startswith("~~~")):
                in_fence = True
                fence = stripped[:3]
                continue
            if in_fence:
                if stripped.startswith(fence):
                    in_fence = False
                    fence = ""
                continue
        elif in_fence:
            continue

        pos = 0
        visible: List[str] = []
        while pos < len(line):
            if in_html:
                end = line.find("-->", pos)
                if end < 0:
                    pos = len(line)
                    break
                in_html = False
                pos = end + 3
                continue

            if active_end is not None:
                html_at = line.find("<!--", pos)
                end_at = line.find(active_end, pos)
                nested = [(marker, line.find(marker, pos)) for marker in all_starts]
                nested = [(marker, at) for marker, at in nested if at >= 0]
                wrong_ends = [(marker, line.find(marker, pos)) for marker in all_ends if marker != active_end]
                wrong_ends = [(marker, at) for marker, at in wrong_ends if at >= 0]
                candidates = [("html", html_at)] if html_at >= 0 else []
                candidates += [("end", end_at)] if end_at >= 0 else []
                candidates += [(f"nested:{marker}", at) for marker, at in nested]
                candidates += [(f"wrong:{marker}", at) for marker, at in wrong_ends]
                if not candidates:
                    active_parts.append(line[pos:])
                    pos = len(line)
                    break
                kind, at = min(candidates, key=lambda item: item[1])
                active_parts.append(line[pos:at])
                if kind == "html":
                    in_html = True
                    pos = at + 4
                    continue
                if kind.startswith("nested:"):
                    raise ValidationError(3, "NESTED_COMMENT", f"nested comment marker at line {line_no}, column {at + 1}")
                if kind.startswith("wrong:"):
                    raise ValidationError(3, "MISMATCHED_COMMENT_END", f"mismatched comment end at line {line_no}, column {at + 1}")
                body = "\n".join(active_parts).strip()
                if body:
                    comments.append(body)
                pos = at + len(active_end)
                active_end = None
                active_start = None
                active_parts = []
                continue

            html_at = line.find("<!--", pos)
            markers = [(marker, line.find(marker, pos)) for marker in all_starts]
            markers += [(marker, line.find(marker, pos)) for marker in all_ends]
            markers = [(marker, at) for marker, at in markers if at >= 0]
            candidates = [("html", html_at)] if html_at >= 0 else []
            candidates += [(marker, at) for marker, at in markers]
            if not candidates:
                visible.append(line[pos:])
                break
            marker, at = min(candidates, key=lambda item: item[1])
            visible.append(line[pos:at])
            if marker == "html":
                in_html = True
                pos = at + 4
                continue
            if marker in all_ends:
                raise ValidationError(3, "STRAY_COMMENT_END", f"stray comment end at line {line_no}, column {at + 1}")
            active_end = all_starts[marker]
            active_start = (line_no, at + 1, marker)
            active_parts = []
            pos = at + len(marker)

        visible_text = "".join(visible).strip()
        if active_end is None and re.match(r"^#{1,6}\s+\S", visible_text):
            headings.append(visible_text)

    if active_end is not None and active_start is not None:
        line_no, column, marker = active_start
        raise ValidationError(3, "UNCLOSED_COMMENT", f"comment opened with {marker} at line {line_no}, column {column} has no {active_end}")
    return ScanResult(comments=comments, headings=headings)


def heading_present(headings: Iterable[str], required: str) -> bool:
    if required == "## Feasibility Hints and Suggestions":
        return any(item in {required, "## Feasibility Hints"} for item in headings)
    return required in headings


def validate_schema(headings: Sequence[str]) -> None:
    missing = [required for required in GEN_REQUIRED if not heading_present(headings, required)]
    forbidden = [heading for heading in headings if heading == "## Claude-Codex Deliberation"]
    if forbidden:
        raise ValidationError(4, "LEGACY_DELIBERATION_SECTION", "pure Codex plans must not contain `## Claude-Codex Deliberation`")
    if missing:
        raise ValidationError(4, "MISSING_REQUIRED_SECTIONS", "missing required sections: " + ", ".join(missing))


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True))


def command_gen(args: argparse.Namespace) -> None:
    input_path = resolve(args.input)
    output_path = resolve(args.output)
    text = require_input(input_path)
    require_new_output(output_path)
    emit({"status": "ok", "mode": "gen", "input": str(input_path), "output": str(output_path), "input_lines": len(text.splitlines())})


def command_refine(args: argparse.Namespace) -> None:
    input_path = resolve(args.input)
    output_path = resolve(args.output) if args.output else input_path
    qa_dir = resolve(args.qa_dir)
    text = require_input(input_path)
    result = scan_plan(text)
    if not result.comments:
        raise ValidationError(3, "NO_COMMENT_BLOCKS", "input contains no valid non-empty comment blocks")
    validate_schema(result.headings)
    require_writable_output(output_path, input_path)
    ensure_qa_dir(qa_dir)
    emit({
        "status": "ok",
        "mode": "refine",
        "input": str(input_path),
        "output": str(output_path),
        "qa_dir": str(qa_dir),
        "comment_count": len(result.comments),
        "execution_mode": "discussion" if args.discussion else "direct" if args.direct else "default",
        "alt_language": args.alt_language or "",
    })


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    gen = sub.add_parser("gen", help="validate draft and new Goal Plan output")
    gen.add_argument("--input", required=True)
    gen.add_argument("--output", required=True)
    gen.set_defaults(func=command_gen)

    refine = sub.add_parser("refine", help="validate annotated pure-Codex plan and outputs")
    refine.add_argument("--input", required=True)
    refine.add_argument("--output")
    refine.add_argument("--qa-dir", default=".codex-humanizer/plan_qa")
    refine.add_argument("--alt-language")
    mode = refine.add_mutually_exclusive_group()
    mode.add_argument("--discussion", action="store_true")
    mode.add_argument("--direct", action="store_true")
    refine.set_defaults(func=command_refine)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
        return 0
    except ValidationError as exc:
        emit({"status": "error", "code": exc.code, "kind": exc.kind, "message": str(exc)})
        return exc.code


if __name__ == "__main__":
    sys.exit(main())
