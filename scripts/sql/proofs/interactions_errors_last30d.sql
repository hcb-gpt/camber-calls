-- Pipeline error sink counts by reason for the last 30 days.
-- Run: scripts/query.sh --file scripts/sql/proofs/interactions_errors_last30d.sql

select
  coalesce(error_reason, '(no_reason)') as error_reason,
  count(*) as row_count,
  min(moved_at_utc) as first_moved_at_utc,
  max(moved_at_utc) as last_moved_at_utc
from public.interactions_errors
where moved_at_utc >= (now() - interval '30 days')
group by 1
order by row_count desc, error_reason asc;

