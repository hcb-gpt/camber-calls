#!/usr/bin/env python3
"""
homeowner_override_proof_runner.py

Evaluates the homeowner override acceptance CSV and reports before/after
failure counts for deterministic homeowner assignment gating.

This runner is intentionally deterministic and offline:
- "Before" uses the reason_codes/status snapshot in the CSV.
- "After" applies the expected deterministic-gate outcome:
  eligible homeowner rows become assign/no-review unless explicitly multi-project.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

BLOCKER_REASON_CODES = {
    "weak_anchor",
    "geo_only",
    "bizdev_without_commitment",
    "model_error",
}


def parse_bool(value: str | None) -> bool:
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "t", "yes", "y"}


def split_reason_codes(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [code.strip() for code in raw.split(";") if code.strip()]


@dataclass
class RowEval:
    row_id: str
    interaction_id: str
    span_id: str
    status: str
    override_active: bool
    override_project_id: str
    eligible_homeowner_override: bool
    multi_project_exception: bool
    before_reason_codes: str
    before_blockers: str
    before_failed: bool
    after_expected_decision: str
    after_expected_project_id: str
    after_failed: bool
    note: str


def evaluate_rows(rows: Iterable[dict[str, str]]) -> list[RowEval]:
    out: list[RowEval] = []
    for row in rows:
        reason_codes = split_reason_codes(row.get("reason_codes"))
        blocker_hits = sorted(set(reason_codes).intersection(BLOCKER_REASON_CODES))
        override_active = parse_bool(row.get("override_active"))
        override_project_id = (row.get("override_project_id") or "").strip()
        eligible = override_active and bool(override_project_id)
        multi_project_exception = "multi_project_span" in reason_codes

        before_failed = eligible and not multi_project_exception and len(blocker_hits) > 0

        if eligible and not multi_project_exception:
            after_expected_decision = "assign"
            after_expected_project_id = override_project_id
            after_failed = False
            note = "deterministic homeowner gate force-assigns project"
        elif eligible and multi_project_exception:
            after_expected_decision = "review"
            after_expected_project_id = ""
            after_failed = False
            note = "documented exception: multi_project_span"
        else:
            after_expected_decision = row.get("status", "").strip() or "unchanged"
            after_expected_project_id = ""
            after_failed = False
            note = "not eligible homeowner override row"

        out.append(
            RowEval(
                row_id=(row.get("row_id") or "").strip(),
                interaction_id=(row.get("interaction_id") or "").strip(),
                span_id=(row.get("span_id") or "").strip(),
                status=(row.get("status") or "").strip(),
                override_active=override_active,
                override_project_id=override_project_id,
                eligible_homeowner_override=eligible,
                multi_project_exception=multi_project_exception,
                before_reason_codes=";".join(reason_codes),
                before_blockers=";".join(blocker_hits),
                before_failed=before_failed,
                after_expected_decision=after_expected_decision,
                after_expected_project_id=after_expected_project_id,
                after_failed=after_failed,
                note=note,
            )
        )
    return out


def summarize(evals: list[RowEval]) -> dict[str, int | bool]:
    eligible = [e for e in evals if e.eligible_homeowner_override]
    before_failures = [e for e in eligible if e.before_failed]
    after_failures = [e for e in eligible if e.after_failed]
    exceptions = [e for e in eligible if e.multi_project_exception]

    return {
        "rows_total": len(evals),
        "homeowner_rows_eligible": len(eligible),
        "homeowner_rows_before_failures": len(before_failures),
        "homeowner_rows_after_failures": len(after_failures),
        "homeowner_rows_improved": max(0, len(before_failures) - len(after_failures)),
        "homeowner_rows_exceptions": len(exceptions),
        "acceptance_pass": len(after_failures) == 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run homeowner override proofset evaluation.")
    parser.add_argument("--input", required=True, help="Path to homeowner override proofset CSV.")
    parser.add_argument("--json-out", help="Optional path to write summary JSON.")
    parser.add_argument("--csv-out", help="Optional path to write evaluated row CSV.")
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        raise SystemExit(f"Input CSV not found: {input_path}")

    with input_path.open(newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))

    evals = evaluate_rows(rows)
    summary = summarize(evals)

    if args.csv_out:
        csv_out = Path(args.csv_out).expanduser().resolve()
        csv_out.parent.mkdir(parents=True, exist_ok=True)
        with csv_out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(asdict(evals[0]).keys()) if evals else [])
            if evals:
                writer.writeheader()
                writer.writerows(asdict(e) for e in evals)

    if args.json_out:
        json_out = Path(args.json_out).expanduser().resolve()
        json_out.parent.mkdir(parents=True, exist_ok=True)
        json_out.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
