ALTER INDEX IF EXISTS idx_cost_code_taxonomy_v2_parent_category 
    RENAME TO idx_cost_code_taxonomy_parent_category;
ALTER INDEX IF EXISTS idx_cost_code_taxonomy_v2_parent_subcategory 
    RENAME TO idx_cost_code_taxonomy_parent_subcategory;
ALTER INDEX IF EXISTS idx_cost_code_taxonomy_v2_row_type 
    RENAME TO idx_cost_code_taxonomy_row_type;;
