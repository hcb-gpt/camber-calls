-- Seed validated contacts from ingestion report
INSERT INTO public.contacts (phone, name, contact_type, company, role, notes)
VALUES
  ('+14042107450', 'Lou Winship',        'client',       NULL,                     'Homeowner',    'Winship project homeowner'),
  ('+17063868967', 'Anthony Cottrell',   'subcontractor','Crossed Chisels, LLC',   'Owner',        'Cabinetry sub; cypress/milling'), 
  ('+17063472615', 'Jordan Foster',      'personal',     NULL,                     'Tenant',       'Lease/property matter'),
  ('+17705278711', 'Flynt Treadaway',    'vendor',       'Carter Lumber, Inc.',    'Sales',        'Lumber sales rep'), 
  ('+17062088041', 'Google Listing Spam','spam',         NULL,                     NULL,           'Robocall; do not call back')
ON CONFLICT (phone) DO UPDATE
  SET name = EXCLUDED.name,
      contact_type = EXCLUDED.contact_type,
      company = EXCLUDED.company,
      role = EXCLUDED.role,
      notes = EXCLUDED.notes,
      updated_at = now();;
