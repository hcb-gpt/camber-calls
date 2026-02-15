-- Proof query for review-span backfill harness.
-- Usage example:
--   psql "$DATABASE_URL" -v target_span_ids="'<uuid>'::uuid,'<uuid>'::uuid" -f scripts/review_span_extraction_proof.sql
--
-- Produces:
--   target_span_count               (number of sampled review spans)
--   recovered_claim_count_total      (all recovered claims for sampled spans)
--   recovered_claims_with_pointer    (claims with transcript pointers)
--   duplicate_key_rows              (sum of duplicate (call_id, source_span_id, claim_type, claim_text))

WITH target_spans AS (
  SELECT unnest(ARRAY[:target_span_ids]) AS span_id
),
claims AS (
  SELECT
    jc.call_id,
    jc.source_span_id,
    jc.claim_type,
    jc.claim_text,
    jc.char_start,
    jc.char_end,
    jc.pointer_type
  FROM target_spans t
  JOIN public.journal_claims jc
    ON jc.source_span_id = t.span_id
  WHERE jc.active = true
),
duplicate_keys AS (
  SELECT
    call_id,
    source_span_id,
    claim_type,
    claim_text,
    COUNT(*) AS claims_per_key
  FROM claims
  GROUP BY 1,2,3,4
  HAVING COUNT(*) > 1
)
SELECT
  (SELECT COUNT(*) FROM target_spans) AS target_span_count,
  (SELECT COUNT(*) FROM claims) AS recovered_claim_count_total,
  (SELECT COUNT(*) FROM claims WHERE char_start IS NOT NULL AND char_end IS NOT NULL AND pointer_type = 'transcript_span') AS recovered_claims_with_pointer,
  (SELECT COALESCE(SUM(claims_per_key - 1), 0) FROM duplicate_keys) AS duplicate_key_rows;
