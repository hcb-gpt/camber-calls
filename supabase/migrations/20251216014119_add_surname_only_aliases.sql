-- Add surname-only aliases for key contacts (common in casual conversation)
UPDATE contacts 
SET aliases = array_append(aliases, 'Winship')
WHERE name = 'Lou Winship';

UPDATE contacts 
SET aliases = array_append(aliases, 'Winship')
WHERE name = 'Blanton Winship';

UPDATE contacts 
SET aliases = array_append(aliases, 'Hurley')
WHERE name = 'Bo Hurley';

UPDATE contacts 
SET aliases = array_append(aliases, 'Hurley')
WHERE name = 'Kaylen Hurley';

UPDATE contacts 
SET aliases = array_append(aliases, 'Woodbery')
WHERE name = 'David Woodbery';

UPDATE contacts 
SET aliases = array_append(aliases, 'Woodbery')
WHERE name = 'Shayelyn Woodbery';

UPDATE contacts 
SET aliases = array_append(aliases, 'Sittler')
WHERE name = 'Zack Sittler' AND contact_type = 'internal';

UPDATE contacts 
SET aliases = array_append(aliases, 'Napier')
WHERE name = 'Daniel Napier';

UPDATE contacts 
SET aliases = array_append(aliases, 'Chastain')
WHERE name = 'Jimmy Chastain';

UPDATE contacts 
SET aliases = array_append(aliases, 'Carter')
WHERE name = 'David Carter';

UPDATE contacts 
SET aliases = array_append(aliases, 'Quevedo')
WHERE name = 'Edenilson Quevedo';

UPDATE contacts 
SET aliases = array_append(aliases, 'Barlow')
WHERE name = 'Chad Barlow';

UPDATE contacts 
SET aliases = array_append(aliases, 'Cottrell')
WHERE name = 'Alicia Cottrell';

UPDATE contacts 
SET aliases = array_append(aliases, 'Cottrell')
WHERE name = 'Anthony Cottrell';
;
