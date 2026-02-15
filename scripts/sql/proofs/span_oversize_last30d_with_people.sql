-- Oversize spans (last 30d) joined to interactions for owner/contact context.
-- Run: scripts/query.sh --file scripts/sql/proofs/span_oversize_last30d_with_people.sql

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
    and (
      length(coalesce(cs.transcript_segment, '')) >= 12000
      or cs.word_count >= 2000
    )
)
select
  s.*,
  i.owner_name,
  i.owner_phone,
  i.contact_name,
  i.contact_phone
from spans s
join public.interactions i on i.interaction_id = s.interaction_id
order by greatest(s.transcript_chars, coalesce(s.word_count, 0)) desc
limit 200;

