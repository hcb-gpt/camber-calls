
-- Move unknown vendors to 'other' contact type
UPDATE contacts SET contact_type = 'other'
WHERE id IN (
    '54775e54-37ce-449b-8791-17cde62fbac2', -- Jeffrey Payne (Howard Payne)
    'c7327d56-ec15-44fc-8b7c-9a432904ba42'  -- Quetion Shelton (PEC)
);
;
