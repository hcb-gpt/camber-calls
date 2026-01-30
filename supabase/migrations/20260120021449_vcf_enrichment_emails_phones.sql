
-- VCF Enrichment: Update existing contacts with new emails and phones

-- Steve Hayes: add email
UPDATE contacts SET email = 'shayes.hhi@gmail.com' 
WHERE name = 'Steve Hayes' AND phone = '+17066144454';

-- John Singleton: add secondary phone from VCF
UPDATE contacts SET secondary_phone = '+17705603045',
    notes = COALESCE(notes, '') || ' | Cell: +17705603045 (from VCF)'
WHERE name = 'John Singleton' AND phone = '+17709239695';

-- Mike Kreikemeier: add secondary phone
UPDATE contacts SET secondary_phone = '+17704421461',
    notes = COALESCE(notes, '') || ' | Cell: +17704421461'
WHERE name = 'Mike Kreikemeier';

-- Blanton Winship: add secondary phones to notes (already has primary)
UPDATE contacts SET notes = COALESCE(notes, '') || ' | Additional: +14047366551, +14046719501'
WHERE name = 'Blanton Winship';

-- Taylor Shannon: update with role from VCF
UPDATE contacts SET role = 'Owner'
WHERE name = 'Taylor Shannon' AND role IS NULL;

-- Zac Line: note that phone is shared with Greg Busch, add Greg's email to notes
UPDATE contacts SET notes = COALESCE(notes, '') || ' | Phone shared with Greg Busch (gb@gregbusch.com)'
WHERE name = 'Zac Line';
;
