
-- Trade normalization per Chad's review

-- 1. Fireplace → Fireplaces
UPDATE contacts SET trade = 'Fireplaces' WHERE trade = 'Fireplace';

-- 2. Landscape variants → Landscaping
UPDATE contacts SET trade = 'Landscaping' WHERE trade IN ('Landscape', 'Landscape Design');

-- 3. Hardscape → Sitework (but NOT Hauling - that goes to Temp Facilities)
UPDATE contacts SET trade = 'Sitework' WHERE trade = 'Hardscape';

-- 4. Landon Hill (roll-off) → Temporary Facilities
UPDATE contacts SET trade = 'Temporary Facilities' WHERE name = 'Landon Hill' AND trade = 'Hauling';

-- 5. Masonry/Brick → Masonry (keep Stone/Masonry separate for suppliers)
UPDATE contacts SET trade = 'Masonry' WHERE trade = 'Masonry/Brick';

-- 6. Granite/Stone → Countertops
UPDATE contacts SET trade = 'Countertops' WHERE trade = 'Granite/Stone';

-- 7. Lumber variants → Lumber
UPDATE contacts SET trade = 'Lumber' WHERE trade = 'Lumber/Materials';

-- 8. Damon (Tree Farm) → change to 'other' contact type (not a construction vendor)
UPDATE contacts SET 
    contact_type = 'other',
    company = 'Damon Tree Farm',
    trade = NULL,
    notes = COALESCE(notes, '') || ' | Christmas tree farm - not construction related'
WHERE name = 'Damon (Tree Farm)' AND trade = 'Trees/Lumber';

-- 9. Power/Electric → Utilities (new trade for utility coordination)
UPDATE contacts SET trade = 'Utilities' WHERE trade = 'Power/Electric';

-- 10. Plumbing Supplies → Plumbing Fixtures
UPDATE contacts SET trade = 'Plumbing Fixtures' WHERE trade = 'Plumbing Supplies';

-- 11. Lighting/Hardware → Lighting
UPDATE contacts SET trade = 'Lighting' WHERE trade = 'Lighting/Hardware';

-- 12. Ryan Olivera (Square Design) → change to 'other' contact type (unknown business)
UPDATE contacts SET contact_type = 'other' WHERE name = 'Ryan Olivera' AND trade = 'Design';

-- 13. Stone/Masonry stays as-is (suppliers separate from installers per Chad)
-- No action needed

-- 14. Paint stays separate from Painting (supplier vs installer pattern)
-- No action needed
;
