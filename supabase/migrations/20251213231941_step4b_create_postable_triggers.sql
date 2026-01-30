DROP TRIGGER IF EXISTS trg_check_postable_vendor_cost_code ON vendor_cost_code_map;
CREATE TRIGGER trg_check_postable_vendor_cost_code
    BEFORE INSERT OR UPDATE ON vendor_cost_code_map
    FOR EACH ROW EXECUTE FUNCTION check_postable_cost_code();

DROP TRIGGER IF EXISTS trg_check_postable_financial_overrides ON financial_overrides;
CREATE TRIGGER trg_check_postable_financial_overrides
    BEFORE INSERT OR UPDATE ON financial_overrides
    FOR EACH ROW EXECUTE FUNCTION check_postable_cost_code();;
