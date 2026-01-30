-- create vocab_hits instrumentation table

create table if not exists public.vocab_hits (
  id uuid primary key default gen_random_uuid(),
  interaction_id uuid references public.interactions(id),
  term text not null,
  hit_count integer default 1,
  transcript_positions jsonb,
  created_at timestamptz default now()
);

create index if not exists idx_vocab_hits_interaction on public.vocab_hits(interaction_id);
create index if not exists idx_vocab_hits_term on public.vocab_hits(term);
;
