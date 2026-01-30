
CREATE TABLE IF NOT EXISTS public.project_attribution_blocklist (
  project_id uuid PRIMARY KEY REFERENCES public.projects(id) ON DELETE CASCADE,
  active boolean NOT NULL DEFAULT true,
  block_mode text NOT NULL DEFAULT 'hard_block',
  reason text,
  blocked_by text,
  effective_from timestamptz NOT NULL DEFAULT NOW(),
  effective_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_project_attribution_blocklist_active
ON public.project_attribution_blocklist(active)
WHERE active = true;

COMMENT ON TABLE public.project_attribution_blocklist IS 'Projects blocked from automatic attribution by router';
COMMENT ON COLUMN public.project_attribution_blocklist.block_mode IS 'hard_block = reject attribution, force_review = route to review queue';
;
