
-- Gate 4: RLS Policies for Journal Tables
-- Service role bypass for pipeline

ALTER TABLE journal_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_open_loops ENABLE ROW LEVEL SECURITY;
ALTER TABLE journal_review_queue ENABLE ROW LEVEL SECURITY;

-- Service role full access
CREATE POLICY "Service role full access on journal_runs" 
  ON journal_runs FOR ALL 
  USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on journal_claims" 
  ON journal_claims FOR ALL 
  USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on journal_conflicts" 
  ON journal_conflicts FOR ALL 
  USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on journal_open_loops" 
  ON journal_open_loops FOR ALL 
  USING (auth.role() = 'service_role');

CREATE POLICY "Service role full access on journal_review_queue" 
  ON journal_review_queue FOR ALL 
  USING (auth.role() = 'service_role');
;
