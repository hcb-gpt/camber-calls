
-- cost_code_taxonomy_v2
-- Load order: create table -> import cost_code_taxonomy_v2.csv

CREATE TABLE IF NOT EXISTS cost_code_taxonomy_v2 (
  code CHAR(4) PRIMARY KEY,
  code_int INT NOT NULL,
  row_type TEXT NOT NULL CHECK (row_type IN ('CATEGORY','SUBCATEGORY','COST_CODE')),
  is_assignable BOOLEAN NOT NULL,
  parent_category_code CHAR(4),
  parent_subcategory_code CHAR(4),
  name TEXT NOT NULL,
  display TEXT NOT NULL,
  division TEXT,
  phase_seq INT,
  description TEXT,
  keywords TEXT,
  default_markup_pct NUMERIC(6,2),
  drift_name_vs_db BOOLEAN DEFAULT FALSE,
  drift_division_vs_db BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cost_code_taxonomy_v2_parent_category ON cost_code_taxonomy_v2(parent_category_code);
CREATE INDEX IF NOT EXISTS idx_cost_code_taxonomy_v2_parent_subcategory ON cost_code_taxonomy_v2(parent_subcategory_code);
CREATE INDEX IF NOT EXISTS idx_cost_code_taxonomy_v2_row_type ON cost_code_taxonomy_v2(row_type);
;
