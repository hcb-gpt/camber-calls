#!/usr/bin/env python3
"""
GT Fresh Candidate Picker v1

Purpose:
- Query `public.v_review_queue_spans` for pending/open span-level review items
- Exclude interaction_ids already present in existing GT label sets / manifests
- Emit a labeling manifest (gt_manifest_v2.csv) with empty GT fields

This is intentionally READ-ONLY (no DB writes).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


MANIFEST_FIELDS = [
    "interaction_id",
    "span_index",
    "expected_project",
    "expected_decision",
    "anchor_quote",
    "bucket_tags",
    "notes",
    "labeled_by",
    "labeled_at_utc",
]


@dataclass
class SpanRow:
    interaction_id: str
    span_id: str
    span_index: int
    review_created_at: str
    contact_name: str
    contact_phone: str
    owner_name: str
    event_at_utc: str
    decision: str
    confidence: Optional[float]
    reason_codes: str
    predicted_project_id: str
    predicted_project_name: str
    transcript_snippet: str


@dataclass
class InteractionBundle:
    interaction_id: str
    spans: List[SpanRow] = field(default_factory=list)
    contact_name: str = ""
    contact_phone: str = ""
    owner_name: str = ""
    newest_review_created_at: str = ""
    event_at_utc: str = ""

    def compute(self, low_conf_threshold: float, floater_names: Set[str]) -> Dict[str, object]:
        confidences = [s.confidence for s in self.spans if isinstance(s.confidence, float)]
        min_conf = min(confidences) if confidences else None
        predicted_ids = {s.predicted_project_id for s in self.spans if s.predicted_project_id}
        predicted_names = {s.predicted_project_name for s in self.spans if s.predicted_project_name}
        transcript_join = " ".join([s.transcript_snippet for s in self.spans]).lower()
        reason_join = " ".join([s.reason_codes for s in self.spans]).lower()

        def contains_voicemail(text: str) -> bool:
            return ("voicemail" in text) or ("voice mail" in text) or ("leave a message" in text)

        is_floater = self.contact_name.strip().lower() in floater_names
        has_voicemail = contains_voicemail(transcript_join) or contains_voicemail(reason_join)
        is_multi_span = len(self.spans) >= 2
        is_multi_project = len(predicted_ids) >= 2
        has_low_conf = (min_conf is not None) and (min_conf < low_conf_threshold)

        return {
            "min_conf": min_conf,
            "predicted_ids": predicted_ids,
            "predicted_names": predicted_names,
            "is_floater": is_floater,
            "has_voicemail": has_voicemail,
            "is_multi_span": is_multi_span,
            "is_multi_project": is_multi_project,
            "has_low_conf": has_low_conf,
        }


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def ensure_env(var: str) -> str:
    val = os.environ.get(var, "").strip()
    if not val:
        raise RuntimeError(f"missing required env var: {var}")
    return val


def run_psql(database_url: str, psql_bin: str, sql: str) -> str:
    cmd = [
        psql_bin,
        database_url,
        "-X",
        "-v",
        "ON_ERROR_STOP=1",
        "-A",
        "-t",
        "-F",
        "\t",
        "-c",
        sql,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"psql_failed: {proc.stderr.strip()}")
    return proc.stdout


def parse_tsv(stdout: str, headers: Sequence[str]) -> List[Dict[str, str]]:
    rows: List[Dict[str, str]] = []
    for line in (stdout or "").splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != len(headers):
            raise RuntimeError(f"unexpected_column_count: got={len(parts)} expected={len(headers)} line={line[:120]}")
        rows.append({headers[i]: parts[i] for i in range(len(headers))})
    return rows


def load_dedupe_interaction_ids(root: Path) -> Set[str]:
    dedupe: Set[str] = set()

    # 1) All GT label sets
    for path in sorted(root.glob("proofs/gt/inputs/**/GT_LABELING.csv")):
        with path.open("r", newline="") as fh:
            reader = csv.DictReader(fh)
            if not reader.fieldnames:
                continue
            # Canonical column is "call_id" in the current GT_LABELING.csv.
            col = "call_id" if "call_id" in reader.fieldnames else "interaction_id"
            for row in reader:
                val = (row.get(col) or "").strip()
                if val:
                    dedupe.add(val)

    # 2) Any prior manifests committed under proofs (reserved fixtures)
    manifest_globs = [
        "proofs/gt/manifests/gt_manifest_v*.csv",
        "proofs/gt/inputs/**/gt_manifest_v*.csv",
        "proofs/gt/inputs/**/gt_manifest_*.csv",
    ]
    for g in manifest_globs:
        for path in sorted(root.glob(g)):
            with path.open("r", newline="") as fh:
                reader = csv.DictReader(fh)
                if not reader.fieldnames or "interaction_id" not in reader.fieldnames:
                    continue
                for row in reader:
                    val = (row.get("interaction_id") or "").strip()
                    if val:
                        dedupe.add(val)

    return dedupe


def default_out_path(root: Path, stamp: str) -> Path:
    # Use UTC date for determinism and to match existing GT inputs layout.
    out_dir = root / "proofs" / "gt" / "inputs" / stamp
    return out_dir / "gt_manifest_v2.csv"


def compact_snippet(text: str, max_len: int = 160) -> str:
    cleaned = re.sub(r"\s+", " ", (text or "").strip())
    if len(cleaned) <= max_len:
        return cleaned
    return cleaned[: max_len - 1].rstrip() + "…"


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description="Pick fresh GT candidates from v_review_queue_spans (read-only).")
    ap.add_argument("--out", default="", help="output csv path (default: proofs/gt/inputs/<UTC-date>/gt_manifest_v2.csv)")
    ap.add_argument("--max-interactions", type=int, default=15, help="target number of unique interaction_ids")
    ap.add_argument("--query-limit", type=int, default=2500, help="max review-queue span rows to consider")
    ap.add_argument("--low-conf-threshold", type=float, default=0.75, help="bucket threshold for low-confidence spans")
    ap.add_argument("--include-shadow", action="store_true", help="include cll_SHADOW_* test interactions (default: excluded)")
    ap.add_argument("--dry-run", action="store_true", help="print selection summary only; do not write file")
    args = ap.parse_args(list(argv))

    root = repo_root()
    database_url = ensure_env("DATABASE_URL")
    psql_bin = os.environ.get("PSQL_PATH", "psql")

    # Dedupe registry (labels + prior manifests)
    dedupe_ids = load_dedupe_interaction_ids(root)

    headers = [
        "interaction_id",
        "span_id",
        "span_index",
        "review_created_at",
        "contact_name",
        "contact_phone",
        "owner_name",
        "event_at_utc",
        "decision",
        "confidence",
        "reason_codes",
        "predicted_project_id",
        "predicted_project_name",
        "transcript_snippet",
    ]

    shadow_filter = "" if args.include_shadow else "and v.interaction_id not like 'cll_SHADOW_%'"

    sql = f"""
with rq as (
  select
    v.interaction_id,
    v.span_id,
    v.review_created_at::text as review_created_at,
    v.review_status,
    v.reason_codes::text as reason_codes,
    v.transcript_snippet,
    v.decision,
    v.confidence,
    v.predicted_project_id
  from public.v_review_queue_spans v
  where v.review_status in ('pending','open')
    and v.span_id is not null
    and v.interaction_id is not null
    {shadow_filter}
  order by v.review_created_at desc
  limit {int(args.query_limit)}
),
spans as (
  select
    rq.*,
    cs.span_index
  from rq
  join public.conversation_spans cs on cs.id = rq.span_id
    and cs.is_superseded = false
)
select
  s.interaction_id,
  s.span_id::text as span_id,
  s.span_index::text as span_index,
  s.review_created_at,
  coalesce(i.contact_name,'') as contact_name,
  coalesce(i.contact_phone,'') as contact_phone,
  coalesce(i.owner_name,'') as owner_name,
  coalesce(i.event_at_utc::text,'') as event_at_utc,
  coalesce(s.decision,'') as decision,
  coalesce(s.confidence::text,'') as confidence,
  coalesce(s.reason_codes,'') as reason_codes,
  coalesce(s.predicted_project_id,'') as predicted_project_id,
  coalesce(p.name,'') as predicted_project_name,
  replace(replace(coalesce(s.transcript_snippet,''), E'\\n',' '), E'\\t',' ') as transcript_snippet
from spans s
left join public.interactions i on i.interaction_id = s.interaction_id
left join public.projects p on p.id::text = s.predicted_project_id
order by s.review_created_at desc, s.interaction_id, s.span_index;
""".strip()

    raw = run_psql(database_url, psql_bin, sql)
    parsed = parse_tsv(raw, headers)

    span_rows: List[SpanRow] = []
    for r in parsed:
        conf_raw = (r.get("confidence") or "").strip()
        conf_val: Optional[float] = None
        if conf_raw:
            try:
                conf_val = float(conf_raw)
            except ValueError:
                conf_val = None

        span_rows.append(
            SpanRow(
                interaction_id=r["interaction_id"],
                span_id=r["span_id"],
                span_index=int(r["span_index"]),
                review_created_at=r["review_created_at"],
                contact_name=r["contact_name"],
                contact_phone=r["contact_phone"],
                owner_name=r["owner_name"],
                event_at_utc=r["event_at_utc"],
                decision=r["decision"],
                confidence=conf_val,
                reason_codes=r["reason_codes"],
                predicted_project_id=r["predicted_project_id"],
                predicted_project_name=r["predicted_project_name"],
                transcript_snippet=r["transcript_snippet"],
            )
        )

    bundles: Dict[str, InteractionBundle] = {}
    for s in span_rows:
        if s.interaction_id in dedupe_ids:
            continue
        b = bundles.get(s.interaction_id)
        if not b:
            b = InteractionBundle(interaction_id=s.interaction_id)
            bundles[s.interaction_id] = b
        b.spans.append(s)
        if s.contact_name and not b.contact_name:
            b.contact_name = s.contact_name
        if s.contact_phone and not b.contact_phone:
            b.contact_phone = s.contact_phone
        if s.owner_name and not b.owner_name:
            b.owner_name = s.owner_name
        if s.event_at_utc and not b.event_at_utc:
            b.event_at_utc = s.event_at_utc
        b.newest_review_created_at = max(b.newest_review_created_at, s.review_created_at)

    # Deterministic feature buckets
    floater_names = {n.lower() for n in ["Randy Booth", "Zack Sittler", "Zachary Sittler", "Zach Sittler"]}

    scored: List[Tuple[str, Dict[str, object]]] = []
    for iid, b in bundles.items():
        meta = b.compute(args.low_conf_threshold, floater_names)
        scored.append((iid, meta))

    # Candidate lists (deterministic ordering: newest review_created_at first)
    def newest_first(iids: Iterable[str]) -> List[str]:
        return sorted(iids, key=lambda x: bundles[x].newest_review_created_at, reverse=True)

    voicemail = newest_first([iid for iid, m in scored if bool(m["has_voicemail"])])
    floater = newest_first([iid for iid, m in scored if bool(m["is_floater"])])
    multi_project = newest_first([iid for iid, m in scored if bool(m["is_multi_project"])])
    low_conf = newest_first([iid for iid, m in scored if bool(m["has_low_conf"])])
    newest_any = newest_first([iid for iid, _ in scored])

    selected: List[str] = []
    selected_set: Set[str] = set()

    def take_from(pool: List[str], k: int) -> None:
        taken = 0
        for iid in pool:
            if len(selected) >= int(args.max_interactions):
                return
            if iid in selected_set:
                continue
            selected.append(iid)
            selected_set.add(iid)
            taken += 1
            if taken >= k or len(selected) >= int(args.max_interactions):
                return

    # Diversity-first selection
    take_from(voicemail, 1)
    take_from(floater, 3)
    take_from(multi_project, 3)
    take_from(low_conf, 5)
    take_from(newest_any, int(args.max_interactions))

    selected = selected[: int(args.max_interactions)]

    # Ensure at least 2 predicted projects represented (best-effort)
    covered_projects: Set[str] = set()
    for iid in selected:
        covered_projects.update({s.predicted_project_name for s in bundles[iid].spans if s.predicted_project_name})

    if len(covered_projects) < 2:
        for iid in newest_any:
            if iid in selected_set:
                continue
            cand_projects = {s.predicted_project_name for s in bundles[iid].spans if s.predicted_project_name}
            if cand_projects and not cand_projects.issubset(covered_projects):
                # Replace the last non-special item if possible
                for j in range(len(selected) - 1, -1, -1):
                    if selected[j] not in (voicemail[:1] + floater[:3] + multi_project[:3]):
                        dropped = selected[j]
                        selected[j] = iid
                        selected_set.remove(dropped)
                        selected_set.add(iid)
                        covered_projects.update(cand_projects)
                        break
            if len(covered_projects) >= 2:
                break

    # Emit manifest rows (one row per span)
    utc_date = dt.datetime.utcnow().strftime("%Y-%m-%d")
    out_path = Path(args.out) if args.out else default_out_path(root, utc_date)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    manifest_rows: List[Dict[str, str]] = []
    for iid in selected:
        b = bundles[iid]
        meta = b.compute(args.low_conf_threshold, floater_names)

        tags: List[str] = []
        if meta["has_voicemail"]:
            tags.append("bucket:voicemail")
        if meta["is_floater"]:
            tags.append("bucket:floater_contact")
        if meta["is_multi_span"]:
            tags.append("bucket:multi_span")
        if meta["is_multi_project"]:
            tags.append("bucket:multi_project_predicted")
        if meta["has_low_conf"]:
            tags.append("bucket:low_confidence")

        # Stable, helpful note header per interaction
        note_prefix = f"contact={b.contact_name or 'unknown'}"

        for s in sorted(b.spans, key=lambda x: x.span_index):
            anchor = compact_snippet(s.transcript_snippet, 160)
            pred = s.predicted_project_name or s.predicted_project_id or ""
            conf_txt = "" if s.confidence is None else f"{s.confidence:.2f}"
            notes = f"{note_prefix}; predicted={pred}; decision={s.decision}; conf={conf_txt}; reasons={compact_snippet(s.reason_codes, 120)}"
            manifest_rows.append(
                {
                    "interaction_id": iid,
                    "span_index": str(s.span_index),
                    "expected_project": "",
                    "expected_decision": "",
                    "anchor_quote": anchor,
                    "bucket_tags": ";".join(tags),
                    "notes": notes,
                    "labeled_by": "",
                    "labeled_at_utc": "",
                }
            )

    # Summary
    print(f"picked_interactions={len(selected)} span_rows={len(manifest_rows)} dedupe_interactions={len(dedupe_ids)}")
    for iid in selected:
        b = bundles[iid]
        meta = b.compute(args.low_conf_threshold, floater_names)
        tag_bits = []
        if meta["has_voicemail"]:
            tag_bits.append("voicemail")
        if meta["is_floater"]:
            tag_bits.append("floater")
        if meta["is_multi_project"]:
            tag_bits.append("multi_project")
        if meta["has_low_conf"]:
            tag_bits.append("low_conf")
        print(f"- {iid} spans={len(b.spans)} contact={b.contact_name or 'unknown'} tags={','.join(tag_bits) or 'none'}")

    if args.dry_run:
        print(f"dry_run=true out={out_path}")
        return 0

    with out_path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=MANIFEST_FIELDS)
        writer.writeheader()
        for row in manifest_rows:
            writer.writerow(row)

    print(f"wrote_manifest={out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
