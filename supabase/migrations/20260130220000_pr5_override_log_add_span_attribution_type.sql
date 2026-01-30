-- PR-5: Human Resolution Endpoint
-- Single-transaction RPC + schema updates for review resolution
--
-- Changes:
-- 1. Expand override_log entity_type constraint to include 'span_attribution'
-- 2. Add idempotency_key column + unique index to override_log
-- 3. Create resolve_review_item() RPC for atomic resolution

begin;

-- ============================================================
-- 1. EXPAND OVERRIDE_LOG ENTITY_TYPE CONSTRAINT
-- ============================================================
alter table public.override_log
  drop constraint if exists chk_override_log_entity_type;

alter table public.override_log
  add constraint chk_override_log_entity_type
  check (entity_type in ('interaction', 'scheduler_item', 'span_attribution'));

comment on constraint chk_override_log_entity_type on public.override_log is
  'Valid entity types for audit: interaction, scheduler_item, span_attribution';

-- ============================================================
-- 2. ADD IDEMPOTENCY_KEY COLUMN + UNIQUE INDEX
-- ============================================================
alter table public.override_log
  add column if not exists idempotency_key text;

create unique index if not exists override_log_idempotency_key_uq
  on public.override_log (idempotency_key)
  where idempotency_key is not null;

comment on column public.override_log.idempotency_key is
  'Unique key for deduplication (e.g., resolve:<review_queue_id>:<project_id>)';

-- ============================================================
-- 3. CREATE RESOLVE_REVIEW_ITEM() RPC
-- ============================================================
-- Atomic resolution: all writes succeed or all fail
-- Returns JSON with results

create or replace function public.resolve_review_item(
  p_review_queue_id uuid,
  p_chosen_project_id uuid,
  p_notes text default null,
  p_user_id text default 'human_reviewer'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_review_item record;
  v_span_id uuid;
  v_interaction_id uuid;
  v_call_id text;
  v_from_value text;
  v_idempotency_key text;
  v_audit_exists boolean;
  v_result jsonb;
  v_scheduler_count int := 0;
  v_claims_count int := 0;
begin
  -- Build idempotency key
  v_idempotency_key := 'resolve:' || p_review_queue_id::text || ':' || p_chosen_project_id::text;

  -- 1. Load review_queue item (lock row for update)
  select * into v_review_item
  from review_queue
  where id = p_review_queue_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'review_queue_item_not_found'
    );
  end if;

  v_span_id := v_review_item.span_id;
  v_interaction_id := v_review_item.interaction_id;

  -- 2. Idempotency check: already resolved?
  if v_review_item.status in ('resolved', 'dismissed') then
    return jsonb_build_object(
      'ok', true,
      'review_queue_id', p_review_queue_id,
      'span_id', v_span_id,
      'interaction_id', v_interaction_id,
      'chosen_project_id', p_chosen_project_id,
      'was_already_resolved', true,
      'updates', jsonb_build_object(
        'span_attributions', false,
        'review_queue', false,
        'override_log', false,
        'scheduler_items', 0,
        'journal_claims', 0
      )
    );
  end if;

  -- Require pending status
  if v_review_item.status != 'pending' then
    return jsonb_build_object(
      'ok', false,
      'error', 'review_queue_item_not_pending',
      'current_status', v_review_item.status
    );
  end if;

  -- 3. Check for existing audit row (idempotency via unique index)
  select exists(
    select 1 from override_log where idempotency_key = v_idempotency_key
  ) into v_audit_exists;

  -- 4. Get current applied_project_id for audit from_value
  if v_span_id is not null then
    select applied_project_id::text into v_from_value
    from span_attributions
    where span_id = v_span_id;
  end if;

  -- 5. Write audit row (skip if duplicate via idempotency_key)
  if not v_audit_exists then
    insert into override_log (
      entity_type,
      entity_id,
      field_name,
      from_value,
      to_value,
      user_id,
      reason,
      review_queue_id,
      idempotency_key
    ) values (
      'span_attribution',
      v_span_id,
      'applied_project_id',
      v_from_value,
      p_chosen_project_id::text,
      p_user_id,
      coalesce(p_notes, 'Resolved via resolve_review_item RPC'),
      p_review_queue_id,
      v_idempotency_key
    )
    on conflict (idempotency_key) where idempotency_key is not null
    do nothing;
  end if;

  -- 6. Update span_attributions (SSOT)
  if v_span_id is not null then
    update span_attributions
    set
      applied_project_id = p_chosen_project_id,
      attribution_lock = 'human',
      needs_review = false,
      applied_at_utc = now()
    where span_id = v_span_id;
  end if;

  -- 7. Resolve review_queue
  update review_queue
  set
    status = 'resolved',
    resolved_at = now(),
    resolved_by = p_user_id,
    resolution_action = 'confirmed',
    resolution_notes = p_notes
  where id = p_review_queue_id
    and status = 'pending';

  -- 8. Update scheduler_items (expanded scope)
  if v_interaction_id is not null then
    with updated as (
      update scheduler_items
      set
        project_id = p_chosen_project_id,
        attribution_status = 'resolved',
        needs_review = false
      where interaction_id = v_interaction_id
      returning id
    )
    select count(*) into v_scheduler_count from updated;
  end if;

  -- 9. Update journal_claims (expanded scope)
  if v_interaction_id is not null then
    -- Get call_id from interactions
    select interaction_id into v_call_id
    from interactions
    where id = v_interaction_id;

    if v_call_id is not null then
      with updated as (
        update journal_claims
        set project_id = p_chosen_project_id
        where call_id = v_call_id
        returning id
      )
      select count(*) into v_claims_count from updated;
    end if;
  end if;

  -- 10. Return success
  return jsonb_build_object(
    'ok', true,
    'review_queue_id', p_review_queue_id,
    'span_id', v_span_id,
    'interaction_id', v_interaction_id,
    'chosen_project_id', p_chosen_project_id,
    'was_already_resolved', false,
    'updates', jsonb_build_object(
      'span_attributions', v_span_id is not null,
      'review_queue', true,
      'override_log', not v_audit_exists,
      'scheduler_items', v_scheduler_count,
      'journal_claims', v_claims_count
    )
  );
end;
$$;

comment on function public.resolve_review_item is
  'Atomic human resolution of a pending review item. Updates SSOT + audit + scheduler + claims in single transaction.';

-- Grant execute to service_role (edge functions use this)
grant execute on function public.resolve_review_item to service_role;

commit;
