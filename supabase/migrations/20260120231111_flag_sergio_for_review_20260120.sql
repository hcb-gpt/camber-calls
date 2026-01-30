-- Flag the two concrete Sergios for Chad review
-- Don't merge yet - need confirmation if same person

UPDATE contacts 
SET notes = COALESCE(notes, '') || ' | REVIEW: May be same person as Sergio (Dove Concrete) +16784145608 - confirm with Chad'
WHERE name = 'Sergio (Concrete)' AND phone = '+14784562630';

UPDATE contacts 
SET notes = COALESCE(notes, '') || ' | REVIEW: May be same person as Sergio (Concrete) +14784562630 - confirm with Chad'
WHERE name = 'Sergio (Dove Concrete)' AND phone = '+16784145608';;
