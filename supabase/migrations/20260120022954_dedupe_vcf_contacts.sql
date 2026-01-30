
-- Deduplicate contacts that were added multiple times

-- Delete duplicate Shannon Hudgins (keep first)
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17708429895'
    ) t WHERE rn > 1
);

-- Delete duplicate Marybeth Hopkins
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17065755153'
    ) t WHERE rn > 1
);

-- Delete duplicate Ag Pro
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17063422332'
    ) t WHERE rn > 1
);

-- Delete duplicate Jody GA Power
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17705500010'
    ) t WHERE rn > 1
);

-- Delete duplicate Jay Bentley
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+14782341444'
    ) t WHERE rn > 1
);

-- Delete duplicate Daniel Napier
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17062407305'
    ) t WHERE rn > 1
);

-- Delete duplicate Marshal Davis
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17068180707'
    ) t WHERE rn > 1
);

-- Delete duplicate Katie Stinnett
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17705499561'
    ) t WHERE rn > 1
);

-- Delete duplicate Lucas Myhre
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+14044238497'
    ) t WHERE rn > 1
);

-- Delete duplicate Cody Patterson
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+14234634028'
    ) t WHERE rn > 1
);

-- Delete duplicate Alex Davis
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17062964493'
    ) t WHERE rn > 1
);

-- Delete duplicate Chris Morgan Glass
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17704828701'
    ) t WHERE rn > 1
);

-- Delete duplicate Social Circle Ace
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17704643354'
    ) t WHERE rn > 1
);

-- Delete duplicate Ross Scott
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17064733618'
    ) t WHERE rn > 1
);

-- Delete duplicate David Carter
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17063192812'
    ) t WHERE rn > 1
);

-- Delete duplicate Miguel Lopez
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17065082511'
    ) t WHERE rn > 1
);

-- Delete duplicate Justin McCrae
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+14045832889'
    ) t WHERE rn > 1
);

-- Delete duplicate Adam Bates
DELETE FROM contacts 
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at) as rn
        FROM contacts WHERE phone = '+17063184201'
    ) t WHERE rn > 1
);

-- Handle the Morgan County shared phone (+17063424373)
-- Keep Abby Willetts as primary, note others
UPDATE contacts SET 
    notes = COALESCE(notes, '') || ' | Same phone: Chuck Jarrell (Director), Shannon Shipp'
WHERE phone = '+17063424373' AND name = 'Abby Willetts';

DELETE FROM contacts 
WHERE phone = '+17063424373' AND name IN ('Chuck Jarrell', 'Shannon Shipp');

-- Handle Air Georgia shared phone
-- Keep as company main line
UPDATE contacts SET 
    name = 'Air Georgia (Main)',
    notes = 'Company main line. Austin Atkinson, Heather Brookshire, Anthony Cato also use this number.'
WHERE phone = '+18339024603' AND name = 'Air Georgia (Company)';

DELETE FROM contacts 
WHERE phone = '+18339024603' AND name != 'Air Georgia (Main)';
;
