-- Add street names as aliases
-- Extract street name by removing leading numbers and trailing suffixes
INSERT INTO project_aliases (id, project_id, alias, alias_type, source, confidence, created_at, created_by)
SELECT 
  gen_random_uuid(),
  p.id,
  LOWER(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          p.street,
          '^[0-9]+\s+',  -- Remove leading numbers
          ''
        ),
        '\s+(Rd|Road|Dr|Drive|St|Street|Ct|Court|Ave|Avenue|Ln|Lane|Way|Blvd|Boulevard|Cir|Circle|Pl|Place)\.?$',
        '',
        'i'  -- Case insensitive
      )
    )
  ),
  'street_name',
  'auto_generated',
  0.85,
  NOW(),
  'data_migration_2026-01-21'
FROM projects p
WHERE p.status = 'active'
  AND p.street IS NOT NULL
  AND p.street != ''
  AND NOT EXISTS (
    SELECT 1 FROM project_aliases pa 
    WHERE pa.project_id = p.id 
    AND LOWER(pa.alias) = LOWER(
      TRIM(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            p.street,
            '^[0-9]+\s+',
            ''
          ),
          '\s+(Rd|Road|Dr|Drive|St|Street|Ct|Court|Ave|Avenue|Ln|Lane|Way|Blvd|Boulevard|Cir|Circle|Pl|Place)\.?$',
          '',
          'i'
        )
      )
    )
  )
ON CONFLICT DO NOTHING;;
