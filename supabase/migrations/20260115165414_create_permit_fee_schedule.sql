-- Create permit fee schedule table for tracking jurisdiction-specific permit types
CREATE TABLE permit_fee_schedule (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  jurisdiction text NOT NULL,
  department text NOT NULL,
  permit_type text NOT NULL,
  permit_subtype text,
  fee_amount numeric(10,2),
  lead_time_days integer,
  lead_time_notes text,
  requirements text[],
  notes text,
  source_url text,
  verified_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(jurisdiction, department, permit_type, permit_subtype)
);

COMMENT ON TABLE permit_fee_schedule IS 'Fee schedules and lead times for permits by jurisdiction/department';
COMMENT ON COLUMN permit_fee_schedule.jurisdiction IS 'County or municipality (e.g., Oconee County)';
COMMENT ON COLUMN permit_fee_schedule.department IS 'Issuing department (e.g., Environmental Health, Building)';
COMMENT ON COLUMN permit_fee_schedule.permit_type IS 'Type of permit (e.g., Septic, Building, Electrical)';
COMMENT ON COLUMN permit_fee_schedule.permit_subtype IS 'Specific variant (e.g., Repair, New, Modification)';
COMMENT ON COLUMN permit_fee_schedule.lead_time_days IS 'Expected processing time in business days';
COMMENT ON COLUMN permit_fee_schedule.requirements IS 'Array of requirements (e.g., soil report, pump-out proof)';;
