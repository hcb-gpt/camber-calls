-- Gate B fix: claim_pointers must support transcript_span pointers (char offsets + verbatim span)

alter table public.claim_pointers
  add column if not exists char_start integer,
  add column if not exists char_end integer,
  add column if not exists span_text text,
  add column if not exists span_hash text;

comment on column public.claim_pointers.char_start is 'Transcript span start offset (character index)';
comment on column public.claim_pointers.char_end is 'Transcript span end offset (character index)';
comment on column public.claim_pointers.span_text is 'Verbatim transcript span text';
comment on column public.claim_pointers.span_hash is 'Deterministic hash of span_text + offsets';;
