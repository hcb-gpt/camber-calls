-- Heuristic oversize span scan for last 30 days (tune thresholds as needed).
-- Run: scripts/query.sh --file scripts/sql/proofs/span_oversize_last30d.sql

with spans as (
  select
    cs.id as span_id,
    cs.interaction_id,
    cs.span_index,
    cs.word_count,
    length(coalesce(cs.transcript_segment, '')) as transcript_chars,
    cs.segment_generation
  from public.conversation_spans cs
  join public.interactions i on i.interaction_id = cs.interaction_id
  where
    cs.is_superseded = false
    and coalesce(i.event_at_utc, i.ingested_at_utc) >= (now() - interval '30 days')
)
select *
from spans
where
  transcript_chars >= 12000
  or word_count >= 2000
order by greatest(transcript_chars, coalesce(word_count, 0)) desc
limit 200;

