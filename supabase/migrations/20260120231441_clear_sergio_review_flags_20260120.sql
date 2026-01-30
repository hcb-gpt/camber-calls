-- Clear review flags now that Sergio is resolved
UPDATE contacts 
SET notes = 'Brian Dove''s concrete crew member - writes English (ESL). CONFIRMED different person from Sergio Framer (Spanish only).'
WHERE name = 'Sergio (Dove Concrete)' AND phone = '+16784145608';;
