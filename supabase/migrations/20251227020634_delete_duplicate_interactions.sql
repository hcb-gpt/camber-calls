
WITH duplicates AS (
    SELECT 
        id,
        interaction_id,
        ROW_NUMBER() OVER (
            PARTITION BY interaction_id 
            ORDER BY ingested_at_utc DESC NULLS LAST, id
        ) as rn
    FROM interactions
    WHERE interaction_id IN (
        SELECT interaction_id 
        FROM interactions 
        GROUP BY interaction_id 
        HAVING COUNT(*) > 1
    )
)
DELETE FROM interactions
WHERE id IN (SELECT id FROM duplicates WHERE rn > 1);
;
