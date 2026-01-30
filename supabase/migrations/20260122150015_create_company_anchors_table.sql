-- Company infrastructure that should NOT be attributed to projects
-- "my shop's in bishop" → Bishop is company overhead, not Bishop project

CREATE TABLE company_anchors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,                    -- 'Zack''s Shop', 'HCB Office'
  anchor_type text NOT NULL,             -- 'facility', 'vehicle', 'storage'
  location_city text,                    -- 'Bishop' (for alias matching)
  location_address text,
  owner_contact_id uuid REFERENCES contacts(id),
  notes text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  
  CONSTRAINT valid_anchor_type CHECK (anchor_type IN ('facility', 'vehicle', 'storage', 'equipment'))
);

-- Index for alias scanner lookups
CREATE INDEX idx_company_anchors_location_city ON company_anchors(LOWER(location_city));

COMMENT ON TABLE company_anchors IS 
  'Company infrastructure locations that serve ALL projects. References to these should NOT trigger project attribution. Example: "my shop in bishop" refers to company facility, not Bishop project.';;
