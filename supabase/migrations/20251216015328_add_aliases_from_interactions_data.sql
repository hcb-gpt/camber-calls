-- Add aliases discovered from interactions CSV data

-- Shayelyn - add the Woodbury misspelling
UPDATE contacts 
SET aliases = array_append(aliases, 'Shayelyn Woodbury')
WHERE name = 'Shayelyn Woodbery' 
AND NOT ('Shayelyn Woodbury' = ANY(aliases));

-- Edenilson - add the full name variations from data
UPDATE contacts 
SET aliases = array_cat(aliases, ARRAY['Edenilson A Rivas Quevedo', 'Edenilson Rivas', 'Eden Quevedo'])
WHERE name = 'Edenilson Quevedo'
AND NOT ('Edenilson A Rivas Quevedo' = ANY(aliases));

-- Gatlin - the data shows "Gatlin Peppers" as contact_name
UPDATE contacts 
SET aliases = array_append(aliases, 'Gatlin Peppers')
WHERE name = 'Gatlin'
AND NOT ('Gatlin Peppers' = ANY(aliases));

-- Jose Araujo - data shows variations
UPDATE contacts 
SET aliases = array_cat(aliases, ARRAY['Jose Araujo', 'Jose'])
WHERE name = 'Jose (Tony) Araujo'
AND NOT ('Jose Araujo' = ANY(aliases));

-- Jordan Foster - "Jordan" appears as standalone
UPDATE contacts 
SET aliases = array_append(aliases, 'Jordan')
WHERE name = 'Jordan Foster'
AND NOT ('Jordan' = ANY(aliases));

-- Julie Skelton appears as "Julie Faulk" in some records (possibly maiden/married name)
UPDATE contacts 
SET aliases = array_cat(aliases, ARRAY['Julie Faulk', 'Julie'])
WHERE name = 'Julie Skelton'
AND NOT ('Julie Faulk' = ANY(aliases));
;
