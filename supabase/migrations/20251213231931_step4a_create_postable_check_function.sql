CREATE OR REPLACE FUNCTION check_postable_cost_code()
RETURNS TRIGGER AS $$
BEGIN
    -- Check for vendor_cost_code_map
    IF TG_TABLE_NAME = 'vendor_cost_code_map' AND NEW.cost_code IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM cost_code_taxonomy 
            WHERE code = NEW.cost_code AND row_type = 'COST_CODE'
        ) THEN
            RAISE EXCEPTION 'cost_code % is not a postable COST_CODE (must have row_type=COST_CODE)', NEW.cost_code;
        END IF;
    END IF;
    
    -- Check for financial_overrides original_cost_code
    IF TG_TABLE_NAME = 'financial_overrides' THEN
        IF NEW.original_cost_code IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM cost_code_taxonomy 
                WHERE code = NEW.original_cost_code AND row_type = 'COST_CODE'
            ) THEN
                RAISE EXCEPTION 'original_cost_code % is not a postable COST_CODE', NEW.original_cost_code;
            END IF;
        END IF;
        
        IF NEW.override_cost_code IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM cost_code_taxonomy 
                WHERE code = NEW.override_cost_code AND row_type = 'COST_CODE'
            ) THEN
                RAISE EXCEPTION 'override_cost_code % is not a postable COST_CODE', NEW.override_cost_code;
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;;
