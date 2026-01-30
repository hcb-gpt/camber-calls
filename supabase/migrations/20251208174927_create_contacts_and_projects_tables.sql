-- Ensure UUID support
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Contacts table
CREATE TABLE IF NOT EXISTS public.contacts (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone        text UNIQUE NOT NULL,
  name         text NOT NULL,
  contact_type text NOT NULL,   -- client|subcontractor|site_supervisor|internal|vendor|personal|unknown
  company      text,
  role         text,
  notes        text,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contacts_phone ON public.contacts(phone);

-- Projects table (structure only for now)
CREATE TABLE IF NOT EXISTS public.projects (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            text NOT NULL,
  aliases         text[] DEFAULT '{}',
  address         text,
  client_name     text,
  client_phone    text,
  status          text DEFAULT 'active',
  buildertrend_id text,
  created_at      timestamptz DEFAULT now(),
  updated_at      timestamptz DEFAULT now()
);

-- Seed high-leverage contacts from master lookup
INSERT INTO public.contacts (phone, name, contact_type, company, role, notes)
VALUES
  ('+17066889158', 'Zachary Sittler', 'internal',       'Heartwood Custom Builders', 'Owner',           'Primary GC/owner number'),
  ('+16074375546', 'Zack Sittler (personal)', 'personal', NULL, NULL, 'Personal cell; rarely used for jobs'),
  ('+17068176088', 'Malcolm Hetzer', 'site_supervisor', 'Hetzer Electric LLC',       'Owner',           'Electrician / site supervisor'),
  ('+17065400877', 'Randy Booth',    'site_supervisor', 'Heartwood Custom Builders', 'Project Manager', 'Internal PM / site supervisor'),
  ('+16788363864', 'Gatlin',         'subcontractor',   'Peppers Heating & Air',     'Technician',      'HVAC sub / tech')
ON CONFLICT (phone) DO UPDATE
  SET name = EXCLUDED.name,
      contact_type = EXCLUDED.contact_type,
      company = EXCLUDED.company,
      role = EXCLUDED.role,
      notes = EXCLUDED.notes,
      updated_at = now();;
