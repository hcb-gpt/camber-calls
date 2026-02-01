-- scripts/gate_pack.sql
-- Gate-pack correctness assertions:
-- 1) gates only consider active spans (is_superseded=false)
-- 2) gates join transcript source from calls_raw
-- 3) open review status set matches canonical expectations
--
-- Executed by scripts/gate_pack.sh inside a transaction and ROLLED BACK.

\set ON_ERROR_STOP on

-- psql variables required:
-- :interaction_id_ok, :interaction_id_bad_gap, :interaction_id_bad_overlap, :interaction_id_bad_single
-- :iid_ok, :iid_gap, :iid_ovl, :iid_single        (uuid)
-- :call_ok, :call_gap, :call_ovl, :call_single    (uuid)

create temp table _gate_results (
  gate text,
  interaction_id text,
  violations int
) on commit drop;

-- ---------- FIXTURE: OK CASE ----------
-- Transcript length 3000; two active spans cover exactly [0,3000)
-- Also includes a superseded span that would violate (ignored).
insert into interactions (id, interaction_id, channel, ingested_at_utc, event_at_utc, transcript_chars)
values (:'iid_ok'::uuid, :'interaction_id_ok', 'call', now(), now(), 3000);

insert into calls_raw (id, interaction_id, channel, transcript, ingested_at_utc, event_at_utc)
values (:'call_ok'::uuid, :'interaction_id_ok', 'call', repeat('A', 3000), now(), now());

insert into conversation_spans (id, interaction_id, span_index, char_start, char_end, transcript_segment, word_count, segmenter_version, segment_reason, segment_generation, is_superseded)
values
  (gen_random_uuid(), :'interaction_id_ok', 0, 0, 1500, repeat('A',1500), 1, 'gatepack', 'ok', 1, false),
  (gen_random_uuid(), :'interaction_id_ok', 1, 1500, 3000, repeat('A',1500), 1, 'gatepack', 'ok', 1, false);

-- Superseded violating span (gap) should be ignored
insert into conversation_spans (id, interaction_id, span_index, char_start, char_end, transcript_segment, word_count, segmenter_version, segment_reason, segment_generation, is_superseded)
values
  (gen_random_uuid(), :'interaction_id_ok', 99, 0, 1000, repeat('A',1000), 1, 'gatepack', 'superseded_violation', 0, true);

-- Review status fixture: only certain statuses are "open"
insert into review_queue (id, interaction_id, span_id, status, created_at)
select gen_random_uuid(), :'interaction_id_ok', cs.id,
       s.status,
       now()
from (values ('open'),('pending'),('queued'),('resolved'),('closed'),('needs_review'),('')) as s(status)
join lateral (select id from conversation_spans cs where cs.interaction_id=:'interaction_id_ok' and cs.is_superseded=false limit 1) cs on true;

-- ---------- FIXTURE: BAD GAP CASE ----------
insert into interactions (id, interaction_id, channel, ingested_at_utc, event_at_utc, transcript_chars)
values (:'iid_gap'::uuid, :'interaction_id_bad_gap', 'call', now(), now(), 3000);

insert into calls_raw (id, interaction_id, channel, transcript, ingested_at_utc, event_at_utc)
values (:'call_gap'::uuid, :'interaction_id_bad_gap', 'call', repeat('B', 3000), now(), now());

-- gap between 1400 and 1600
insert into conversation_spans (id, interaction_id, span_index, char_start, char_end, transcript_segment, word_count, segmenter_version, segment_reason, segment_generation, is_superseded)
values
  (gen_random_uuid(), :'interaction_id_bad_gap', 0, 0, 1400, repeat('B',1400), 1, 'gatepack', 'gap', 1, false),
  (gen_random_uuid(), :'interaction_id_bad_gap', 1, 1600, 3000, repeat('B',1400), 1, 'gatepack', 'gap', 1, false);

-- ---------- FIXTURE: BAD OVERLAP CASE ----------
insert into interactions (id, interaction_id, channel, ingested_at_utc, event_at_utc, transcript_chars)
values (:'iid_ovl'::uuid, :'interaction_id_bad_overlap', 'call', now(), now(), 3000);

insert into calls_raw (id, interaction_id, channel, transcript, ingested_at_utc, event_at_utc)
values (:'call_ovl'::uuid, :'interaction_id_bad_overlap', 'call', repeat('C', 3000), now(), now());

-- overlap 1400..1600
insert into conversation_spans (id, interaction_id, span_index, char_start, char_end, transcript_segment, word_count, segmenter_version, segment_reason, segment_generation, is_superseded)
values
  (gen_random_uuid(), :'interaction_id_bad_overlap', 0, 0, 1600, repeat('C',1600), 1, 'gatepack', 'overlap', 1, false),
  (gen_random_uuid(), :'interaction_id_bad_overlap', 1, 1400, 3000, repeat('C',1600), 1, 'gatepack', 'overlap', 1, false);

-- ---------- FIXTURE: BAD SINGLE-SPAN CASE ----------
insert into interactions (id, interaction_id, channel, ingested_at_utc, event_at_utc, transcript_chars)
values (:'iid_single'::uuid, :'interaction_id_bad_single', 'call', now(), now(), 3000);

insert into calls_raw (id, interaction_id, channel, transcript, ingested_at_utc, event_at_utc)
values (:'call_single'::uuid, :'interaction_id_bad_single', 'call', repeat('D', 3000), now(), now());

insert into conversation_spans (id, interaction_id, span_index, char_start, char_end, transcript_segment, word_count, segmenter_version, segment_reason, segment_generation, is_superseded)
values
  (gen_random_uuid(), :'interaction_id_bad_single', 0, 0, 3000, repeat('D',3000), 1, 'gatepack', 'single', 1, false);

-- ---------- GATE IMPLEMENTATIONS ----------
with spans as (
  select cs.*
  from conversation_spans cs
  where cs.interaction_id in (:'interaction_id_ok', :'interaction_id_bad_gap', :'interaction_id_bad_overlap', :'interaction_id_bad_single')
    and coalesce(cs.is_superseded,false)=false
),
tlen as (
  select interaction_id, length(transcript) as chars
  from calls_raw
  where interaction_id in (:'interaction_id_ok', :'interaction_id_bad_gap', :'interaction_id_bad_overlap', :'interaction_id_bad_single')
),
active_span_counts as (
  select interaction_id, count(*) as spans_active
  from spans
  group by 1
),
gate_single_span as (
  select t.interaction_id
  from tlen t
  join active_span_counts c using (interaction_id)
  where t.chars > 2000 and c.spans_active <= 1
),
ordered as (
  select s.*,
         lag(char_end) over (partition by interaction_id order by span_index) as prev_end
  from spans s
),
gaps as (
  select interaction_id
  from ordered
  where prev_end is not null and char_start > prev_end
  group by 1
),
overlaps as (
  select interaction_id
  from ordered
  where prev_end is not null and char_start < prev_end
  group by 1
),
open_review as (
  select rq.*
  from review_queue rq
  where rq.interaction_id=:'interaction_id_ok'
    and coalesce(rq.status,'') in ('open','pending','new','queued','needs_review','')
)
insert into _gate_results(gate, interaction_id, violations)
select 'single_span_long', interaction_id, 1 from gate_single_span
union all
select 'gap_violation', interaction_id, 1 from gaps
union all
select 'overlap_violation', interaction_id, 1 from overlaps;

-- ---------- ASSERTIONS ----------
do $$
declare v int;
begin
  select count(*) into v from _gate_results where interaction_id = :'interaction_id_ok';
  if v <> 0 then
    raise exception 'gate_pack_assertion_failed: ok_case_has_violations count=%', v;
  end if;
end $$;

do $$
declare v int;
begin
  select count(*) into v from _gate_results where gate='gap_violation' and interaction_id = :'interaction_id_bad_gap';
  if v = 0 then raise exception 'gate_pack_assertion_failed: gap_case_not_detected'; end if;

  select count(*) into v from _gate_results where gate='overlap_violation' and interaction_id = :'interaction_id_bad_overlap';
  if v = 0 then raise exception 'gate_pack_assertion_failed: overlap_case_not_detected'; end if;

  select count(*) into v from _gate_results where gate='single_span_long' and interaction_id = :'interaction_id_bad_single';
  if v = 0 then raise exception 'gate_pack_assertion_failed: single_span_case_not_detected'; end if;
end $$;

do $$
declare v int;
begin
  -- If gates accidentally include superseded spans, OK case would be flagged due to superseded gap span.
  select count(*) into v from _gate_results where interaction_id = :'interaction_id_ok';
  if v <> 0 then
    raise exception 'gate_pack_assertion_failed: superseded_rows_leaking_into_gate';
  end if;
end $$;

do $$
declare v int;
begin
  -- inserted: open,pending,queued,needs_review,'' are counted => 5
  select count(*) into v from open_review;
  if v <> 5 then
    raise exception 'gate_pack_assertion_failed: open_review_status_set_mismatch count=%', v;
  end if;
end $$;

select 'GATEPACK|PASS|assertions_ok=true' as receipt;
