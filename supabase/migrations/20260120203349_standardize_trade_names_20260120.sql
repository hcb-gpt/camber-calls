
-- Standardize trade naming
UPDATE contacts SET trade = 'Lumber' WHERE trade = 'Lumber Supply';
UPDATE contacts SET trade = 'Masonry' WHERE trade = 'Stone/Masonry';
UPDATE contacts SET trade = 'Painting' WHERE trade = 'Paint';
;
