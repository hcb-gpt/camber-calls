-- Auto-trigger compute_pointer_v174() on journal_claims INSERT
-- Safety: does NOT block claim insert if pointer computation fails.
-- Requires: compute_pointer_v174(claim_id uuid) exists.

-- 1) Trigger function
CREATE OR REPLACE FUNCTION public.trg_compute_pointer_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only compute if span_text exists but char_start is null
  IF NEW.span_text IS NOT NULL AND NEW.char_start IS NULL THEN
    BEGIN
      PERFORM public.compute_pointer_v174(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- Do not block inserts; surface warning for observability
      RAISE WARNING 'compute_pointer_v174 failed for journal_claims.id=%: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- 2) Trigger
DROP TRIGGER IF EXISTS trg_journal_claim_compute_pointer ON public.journal_claims;

CREATE TRIGGER trg_journal_claim_compute_pointer
AFTER INSERT ON public.journal_claims
FOR EACH ROW
WHEN (NEW.span_text IS NOT NULL AND NEW.char_start IS NULL)
EXECUTE FUNCTION public.trg_compute_pointer_on_insert();;
