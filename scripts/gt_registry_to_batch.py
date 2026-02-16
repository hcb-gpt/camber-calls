#!/usr/bin/env python3
"""
Convert gt_registry_v1.jsonl to gt_batch_v1 CSV for gt_batch_runner.py.

Usage:
    python3 scripts/gt_registry_to_batch.py \
        --input artifacts/gt/registry/gt_registry_v1.jsonl \
        --output artifacts/gt/batches/gt_batch_v1_full.csv
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

BATCH_FIELDS = [
    "row_id",
    "interaction_id",
    "span_index",
    "span_id",
    "expected_project_id",
    "expected_project_name_contains",
    "expected_decision",
    "notes",
    "tags",
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert GT registry JSONL to batch CSV")
    parser.add_argument("--input", required=True, help="path to gt_registry_v1.jsonl")
    parser.add_argument("--output", required=True, help="output CSV path")
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.exists():
        print(f"ERROR: input not found: {input_path}", file=sys.stderr)
        return 1

    rows = []
    with input_path.open("r", encoding="utf-8") as fh:
        for idx, line in enumerate(fh, start=1):
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            rows.append({
                "row_id": f"gt_{idx:04d}",
                "interaction_id": entry.get("interaction_id", ""),
                "span_index": str(entry.get("span_index", 0)),
                "span_id": "",
                "expected_project_id": "",
                "expected_project_name_contains": entry.get("expected_project", ""),
                "expected_decision": entry.get("expected_decision", ""),
                "notes": entry.get("notes", ""),
                "tags": entry.get("bucket_tags", ""),
            })

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with output_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=BATCH_FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)

    print(f"Converted {len(rows)} rows -> {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
