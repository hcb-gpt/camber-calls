
-- Add secondary phone numbers from Beside data

-- Austin Atkinson: add cell phone
UPDATE contacts 
SET secondary_phone = '+17703982877', 
    notes = COALESCE(notes, '') || ' | Beside cell: +17703982877 (PM, Air Georgia)'
WHERE name = 'Austin Atkinson' AND phone = '+17702968422';

-- Robyn Holland: add cell phone (currently has office)
UPDATE contacts 
SET secondary_phone = '+17707841207',
    notes = COALESCE(notes, '') || ' | Cell: +17707841207'
WHERE name = 'Robyn Holland';

-- Anthony Cato: add personal cell
UPDATE contacts 
SET secondary_phone = '+14703071637',
    notes = COALESCE(notes, '') || ' | Personal cell: +14703071637'
WHERE name = 'Anthony Cato';

-- Brandon Hightower: add company number
UPDATE contacts 
SET secondary_phone = '+17063421104',
    notes = COALESCE(notes, '') || ' | Company (Georgia Civil): +17063421104'
WHERE name = 'Brandon Hightower' AND phone = '+16786151584';

-- Name correction: Waymon → Wayman
UPDATE contacts SET name = 'Wayman Bryan' WHERE name = 'Waymon Bryan';
;
