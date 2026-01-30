-- Add county column to projects
ALTER TABLE projects ADD COLUMN IF NOT EXISTS county TEXT;

-- Create city-to-county lookup table for Georgia
CREATE TABLE IF NOT EXISTS city_county_lookup (
  city TEXT PRIMARY KEY,
  county TEXT NOT NULL,
  state TEXT DEFAULT 'GA'
);

-- Populate with known Georgia cities in the HCB service area
INSERT INTO city_county_lookup (city, county) VALUES
  ('Madison', 'Morgan County'),
  ('Watkinsville', 'Oconee County'),
  ('Athens', 'Clarke County'),
  ('Bishop', 'Oconee County'),
  ('Buckhead', 'Morgan County'),
  ('Sparta', 'Hancock County'),
  ('Greensboro', 'Greene County'),
  ('Eatonton', 'Putnam County'),
  ('Monroe', 'Walton County'),
  ('Social Circle', 'Walton County'),
  ('Rutledge', 'Morgan County'),
  ('Winterville', 'Clarke County'),
  ('Bogart', 'Oconee County'),
  ('Statham', 'Barrow County'),
  ('Farmington', 'Oconee County')
ON CONFLICT (city) DO NOTHING;

-- Backfill county on existing projects
UPDATE projects p
SET county = ccl.county
FROM city_county_lookup ccl
WHERE LOWER(TRIM(p.city)) = LOWER(ccl.city)
  AND p.county IS NULL;;
