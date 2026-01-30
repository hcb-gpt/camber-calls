alter table public.calls_raw add column if not exists recording_url text;
alter table public.calls_raw add column if not exists recording_url_captured_at timestamp with time zone;
create index if not exists calls_raw_recording_url_idx on public.calls_raw (recording_url);;
