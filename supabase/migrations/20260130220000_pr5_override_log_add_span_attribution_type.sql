-- PR-5: Allow 'span_attribution' in override_log entity_type
-- Human resolution endpoint writes audit rows for span-level resolutions

begin;

-- Drop and recreate the check constraint to include span_attribution
alter table public.override_log
  drop constraint if exists chk_override_log_entity_type;

alter table public.override_log
  add constraint chk_override_log_entity_type
  check (entity_type in ('interaction', 'scheduler_item', 'span_attribution'));

comment on constraint chk_override_log_entity_type on public.override_log is
  'Valid entity types for audit: interaction, scheduler_item, span_attribution';

commit;
