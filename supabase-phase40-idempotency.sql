-- Phase 40: atomic idempotency for cloud snapshot pushes.
-- Apply in Supabase SQL Editor AFTER supabase-schema.sql and supabase-phase27.sql.
-- This makes an identical retry of the same branch/revision/payload return its original result.

create table if not exists public.branch_sync_requests (
  branch_id text not null,
  request_id text not null,
  payload_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (branch_id, request_id)
);
create index if not exists branch_sync_requests_created_idx
  on public.branch_sync_requests (created_at desc);
alter table public.branch_sync_requests enable row level security;
-- No client policies; access only through the server service-role connection.

create or replace function public.push_branch_snapshot_idempotent(
  p_branch_id text,
  p_expected_revision bigint,
  p_snapshot jsonb,
  p_request_id text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  prior public.branch_sync_requests%rowtype;
  result_value jsonb;
  payload_fingerprint text;
  stamp timestamptz := now();
begin
  if p_branch_id is null or length(p_branch_id) < 2 or length(p_branch_id) > 64 then
    raise exception 'invalid branch id';
  end if;
  if p_request_id is null or p_request_id !~ '^[A-Za-z0-9_-]{16,100}$' then
    raise exception 'invalid request id';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'invalid expected revision';
  end if;
  if jsonb_typeof(p_snapshot) <> 'object' or jsonb_typeof(p_snapshot->'products') <> 'array' or jsonb_typeof(p_snapshot->'sales') <> 'array' then
    raise exception 'invalid snapshot';
  end if;
  payload_fingerprint := md5(p_expected_revision::text || ':' || p_snapshot::text);

  -- Serialize the idempotency check and snapshot write, including requests from two server workers.
  perform pg_advisory_xact_lock(hashtextextended(p_branch_id || ':' || p_request_id, 0));
  select * into prior from public.branch_sync_requests
    where branch_id=p_branch_id and request_id=p_request_id;
  if found then
    if prior.payload_hash <> payload_fingerprint then
      return jsonb_build_object('ok',false,'conflict',true,'idempotency_key_reused',true,
        'error','request_id reused with a different payload');
    end if;
    return prior.result || jsonb_build_object('replayed',true);
  end if;

  result_value := public.push_branch_snapshot(p_branch_id,p_expected_revision,p_snapshot);
  insert into public.branch_sync_requests(branch_id,request_id,payload_hash,result,created_at)
    values (p_branch_id,p_request_id,payload_fingerprint,result_value,stamp);
  return result_value || jsonb_build_object('replayed',false);
end; $$;

revoke all on function public.push_branch_snapshot_idempotent(text,bigint,jsonb,text) from public, anon, authenticated;
grant execute on function public.push_branch_snapshot_idempotent(text,bigint,jsonb,text) to service_role;
