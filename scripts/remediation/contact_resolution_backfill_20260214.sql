-- Contact resolution remediation backfill (DATA-4)
-- Scope:
-- 1) Backfill interactions.contact_id/contact_name for NULL-contact calls where digits-normalized phone matches exactly 1 contact
-- 2) Backfill calls_raw.raw_snapshot_json.contact_id for those same calls
-- 3) Create contacts for top-4 unmatched numbers and backfill their calls
-- 4) Do not touch ambiguous number 17062969099; do not act on missing-phone calls

BEGIN;

-- ----------
-- Helpers: digits-normalized view of NULL-contact calls
-- ----------
WITH null_calls AS (
  SELECT
    cr.interaction_id,
    cr.other_party_phone,
    cr.other_party_name,
    regexp_replace(coalesce(cr.other_party_phone,''),'[^0-9]','', 'g') AS digits
  FROM calls_raw cr
  WHERE cr.other_party_name IS NULL
), contact_numbers AS (
  SELECT id AS contact_id, name AS contact_name,
         regexp_replace(coalesce(phone,''),'[^0-9]','', 'g') AS digits
  FROM contacts
  UNION ALL
  SELECT id AS contact_id, name AS contact_name,
         regexp_replace(coalesce(secondary_phone,''),'[^0-9]','', 'g') AS digits
  FROM contacts
), contact_counts AS (
  SELECT digits, COUNT(*) AS match_count
  FROM contact_numbers
  WHERE digits <> ''
  GROUP BY digits
), resolvable AS (
  SELECT nc.interaction_id, nc.other_party_phone, cn.contact_id, cn.contact_name
  FROM null_calls nc
  JOIN contact_counts cc ON cc.digits = nc.digits AND cc.match_count = 1
  JOIN contact_numbers cn ON cn.digits = nc.digits
  WHERE nc.digits <> ''
),
-- ----------
-- 1) Backfill interactions for resolvable calls
-- ----------
updated_interactions AS (
  UPDATE interactions i
  SET contact_id = r.contact_id,
      contact_name = r.contact_name
  FROM resolvable r
  WHERE i.interaction_id = r.interaction_id
    AND (i.contact_id IS NULL OR i.contact_name IS NULL)
  RETURNING i.interaction_id
),
-- ----------
-- 2) Backfill calls_raw.raw_snapshot_json.contact_id
-- ----------
updated_calls_raw AS (
  UPDATE calls_raw cr
  SET raw_snapshot_json = jsonb_set(
        COALESCE(cr.raw_snapshot_json, '{}'::jsonb),
        '{contact_id}',
        to_jsonb(r.contact_id::text),
        true
      )
  FROM resolvable r
  WHERE cr.interaction_id = r.interaction_id
  RETURNING cr.interaction_id
)
SELECT
  (SELECT COUNT(*) FROM updated_interactions) AS interactions_updated,
  (SELECT COUNT(*) FROM updated_calls_raw) AS calls_raw_updated;

-- ----------
-- 3) Create contacts for top-4 unmatched numbers (per STRAT directive)
-- Note: phone_digits is generated; do not insert it directly.
-- contact_type is NOT NULL; set to 'unknown'.
-- ----------
INSERT INTO contacts (id, name, phone, contact_type, source, created_at, updated_at)
SELECT
  gen_random_uuid() AS id,
  'Unknown - ' || v.phone AS name,
  v.phone AS phone,
  'unknown' AS contact_type,
  'contact_resolution_backfill' AS source,
  NOW() AS created_at,
  NOW() AS updated_at
FROM (
  VALUES
    ('+16787791746'),
    ('+17348008330'),
    ('+17068160696'),
    ('+14045559876')
) AS v(phone)
WHERE NOT EXISTS (
  SELECT 1 FROM contacts c
  WHERE c.phone_digits = regexp_replace(v.phone,'[^0-9]','', 'g')
     OR c.secondary_phone_digits = regexp_replace(v.phone,'[^0-9]','', 'g')
);

-- ----------
-- 4) Backfill calls for the 4 newly-created contacts
-- ----------
WITH new_contacts AS (
  SELECT id AS contact_id, name AS contact_name, phone_digits
  FROM contacts
  WHERE source = 'contact_resolution_backfill'
    AND phone_digits IN ('16787791746','17348008330','17068160696','14045559876')
), null_calls AS (
  SELECT cr.interaction_id,
    regexp_replace(coalesce(cr.other_party_phone,''),'[^0-9]','', 'g') AS digits
  FROM calls_raw cr
  WHERE cr.other_party_name IS NULL
),
matched AS (
  SELECT nc.interaction_id, c.contact_id, c.contact_name
  FROM null_calls nc
  JOIN new_contacts c ON c.phone_digits = nc.digits
)
UPDATE interactions i
SET contact_id = m.contact_id,
    contact_name = m.contact_name
FROM matched m
WHERE i.interaction_id = m.interaction_id
  AND (i.contact_id IS NULL OR i.contact_name IS NULL);

WITH new_contacts AS (
  SELECT id AS contact_id, phone_digits
  FROM contacts
  WHERE source = 'contact_resolution_backfill'
    AND phone_digits IN ('16787791746','17348008330','17068160696','14045559876')
), null_calls AS (
  SELECT cr.interaction_id,
    regexp_replace(coalesce(cr.other_party_phone,''),'[^0-9]','', 'g') AS digits
  FROM calls_raw cr
  WHERE cr.other_party_name IS NULL
),
matched AS (
  SELECT nc.interaction_id, c.contact_id
  FROM null_calls nc
  JOIN new_contacts c ON c.phone_digits = nc.digits
)
UPDATE calls_raw cr
SET raw_snapshot_json = jsonb_set(
      COALESCE(cr.raw_snapshot_json, '{}'::jsonb),
      '{contact_id}',
      to_jsonb(m.contact_id::text),
      true
    )
FROM matched m
WHERE cr.interaction_id = m.interaction_id;

COMMIT;
