DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'interactions'
      AND column_name = 'attribution_lock'
  ) THEN
    ALTER TABLE interactions
    ADD COLUMN attribution_lock TEXT DEFAULT NULL;

    COMMENT ON COLUMN interactions.attribution_lock IS
      'Lock hierarchy: human_review (HARD) > ai_review (SOFT) > NULL (unlocked). human_review = absolute lock, AI reruns MUST skip. ai_review = soft lock, can be overridden with +0.15 confidence margin.';
  END IF;
END $$;

-- Add check constraint for valid values (also idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'interactions'
      AND constraint_name = 'interactions_attribution_lock_check'
  ) THEN
    ALTER TABLE interactions
    ADD CONSTRAINT interactions_attribution_lock_check
    CHECK (attribution_lock IS NULL OR attribution_lock IN ('human_review', 'ai_review'));
  END IF;
END $$;;
