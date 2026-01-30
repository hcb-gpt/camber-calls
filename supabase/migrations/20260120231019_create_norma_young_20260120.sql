-- Create Norma Young - Brian Young's spouse, co-client on Young Residence
-- Phone placeholder until confirmed
INSERT INTO contacts (id, phone, name, email, contact_type, notes)
VALUES (
  gen_random_uuid(),
  '+10000000004',  -- placeholder
  'Norma Young',
  'normayoung@charter.net',
  'client',
  'Brian Young spouse. Co-client on Young Residence (Red Oak Court). PLACEHOLDER PHONE - needs real number.'
);;
