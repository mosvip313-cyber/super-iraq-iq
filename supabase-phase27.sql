-- Apply in Supabase SQL Editor after the existing schema.
-- Phase 27: revision history and atomic optimistic-concurrency sync.
create table if not exists public.branch_snapshot_history (
  id bigint generated always as identity primary key,
  branch_id text not null,
  revision bigint not null,
  created_at timestamptz not null default now(),
  reason text not null default 'sync-push',
  snapshot jsonb not null,
  unique (branch_id, revision)
);
create index if not exists branch_snapshot_history_branch_revision_idx
  on public.branch_snapshot_history (branch_id, revision desc);
alter table public.branch_snapshot_history enable row level security;
-- No client-facing policies. Access only through the server's service-role connection.

create or replace function public.push_branch_snapshot(
  p_branch_id text, p_expected_revision bigint, p_snapshot jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare current_revision bigint; next_revision bigint; stamp timestamptz := now();
begin
  if p_branch_id is null or length(p_branch_id) < 2 or length(p_branch_id) > 64 then
    raise exception 'invalid branch id';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid expected revision';
  end if;
  if jsonb_typeof(p_snapshot) <> 'object' or jsonb_typeof(p_snapshot->'products') <> 'array' or jsonb_typeof(p_snapshot->'sales') <> 'array' then
    raise exception 'invalid snapshot';
  end if;
  -- Serialize pushes per branch to avoid read-then-write races.
  insert into public.branch_snapshots(branch_id, revision, updated_at, snapshot)
    values (p_branch_id, 0, stamp, jsonb_build_object('products','[]'::jsonb,'sales','[]'::jsonb))
    on conflict (branch_id) do nothing;
  select revision into current_revision from public.branch_snapshots where branch_id=p_branch_id for update;
  if current_revision <> p_expected_revision then
    return jsonb_build_object('ok',false,'revision',current_revision);
  end if;
  next_revision := current_revision + 1;
  insert into public.branch_snapshot_history(branch_id,revision,created_at,reason,snapshot)
    select p_branch_id, current_revision, stamp, 'before-sync-push', snapshot
    from public.branch_snapshots where branch_id=p_branch_id and current_revision > 0
    on conflict (branch_id,revision) do nothing;
  update public.branch_snapshots set revision=next_revision, updated_at=stamp, snapshot=p_snapshot where branch_id=p_branch_id;
  insert into public.branch_snapshot_history(branch_id,revision,created_at,reason,snapshot)
    values (p_branch_id,next_revision,stamp,'sync-push',p_snapshot) on conflict (branch_id,revision) do nothing;
  return jsonb_build_object('ok',true,'revision',next_revision,'updated_at',stamp);
end; $$;
revoke all on function public.push_branch_snapshot(text,bigint,jsonb) from public, anon, authenticated;
grant execute on function public.push_branch_snapshot(text,bigint,jsonb) to service_role;
