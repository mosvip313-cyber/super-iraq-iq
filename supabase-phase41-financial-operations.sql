-- Phase 41: atomic financial operations, idempotency and unique accounting entries.
-- Run after supabase-schema.sql and supabase-phase40-idempotency.sql.
create table if not exists public.financial_operations (
  id bigint generated always as identity primary key,
  branch_id text not null,
  operation_id text not null,
  operation_type text not null check (operation_type in ('sale','collection','expense')),
  payload_hash text not null,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  unique (branch_id, operation_id)
);
create index if not exists financial_operations_branch_created_idx on public.financial_operations(branch_id, created_at desc);
alter table public.financial_operations enable row level security;

create table if not exists public.financial_invoices (
  id bigint generated always as identity primary key,
  branch_id text not null,
  operation_id text not null,
  document_type text not null check (document_type in ('sale','expense')),
  invoice_no text not null,
  amount_iqd numeric(18,2) not null check (amount_iqd > 0),
  paid_iqd numeric(18,2) not null default 0 check (paid_iqd >= 0),
  remaining_iqd numeric(18,2) not null default 0 check (remaining_iqd >= 0),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (branch_id, document_type, invoice_no),
  unique (branch_id, operation_id)
);
alter table public.financial_invoices enable row level security;

create table if not exists public.accounting_entries (
  id bigint generated always as identity primary key,
  branch_id text not null,
  operation_id text not null,
  line_no integer not null check (line_no > 0),
  account_code text not null,
  debit_iqd numeric(18,2) not null default 0 check (debit_iqd >= 0),
  credit_iqd numeric(18,2) not null default 0 check (credit_iqd >= 0),
  currency text not null default 'IQD' check (currency in ('IQD','USD')),
  memo text not null default '',
  created_at timestamptz not null default now(),
  unique (branch_id, operation_id, line_no),
  check (not (debit_iqd > 0 and credit_iqd > 0))
);
create index if not exists accounting_entries_branch_created_idx on public.accounting_entries(branch_id, created_at desc);
alter table public.accounting_entries enable row level security;

-- Phase 43-44: server-authoritative inventory balance and immutable sale movements.
-- Initial stock is seeded from the first accepted sale's stockBefore value only when
-- the product has no server row yet; subsequent sales always lock/read server balance.
create table if not exists public.branch_inventory_stock (
  branch_id text not null,
  product_id text not null,
  qty_on_hand numeric(18,3) not null check (qty_on_hand >= 0),
  updated_at timestamptz not null default now(),
  primary key (branch_id, product_id)
);
alter table public.branch_inventory_stock enable row level security;
create table if not exists public.inventory_stock_movements (
  id bigint generated always as identity primary key,
  branch_id text not null,
  operation_id text not null,
  product_id text not null,
  qty_delta numeric(18,3) not null,
  qty_after numeric(18,3) not null check (qty_after >= 0),
  movement_type text not null check (movement_type in ('sale','adjustment','purchase','return')),
  created_at timestamptz not null default now(),
  unique (branch_id, operation_id, product_id)
);
create index if not exists inventory_stock_movements_branch_created_idx on public.inventory_stock_movements(branch_id,created_at desc);
alter table public.inventory_stock_movements enable row level security;

create or replace function public.record_financial_operation(
  p_branch_id text,
  p_operation_id text,
  p_operation_type text,
  p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  prior public.financial_operations%rowtype;
  payload_fingerprint text;
  amount numeric(18,2);
  paid numeric(18,2);
  remaining numeric(18,2);
  invoice_no text;
  result_value jsonb;
  currency_value text;
  details_value jsonb;
  item_value jsonb;
  product_key text;
  item_qty numeric(18,3);
  stock_before numeric(18,3);
  stock_current numeric(18,3);
  stock_after numeric(18,3);
begin
  if p_branch_id is null or p_branch_id !~ '^[A-Za-z0-9_-]{2,64}$' then
    return jsonb_build_object('ok',false,'error','invalid_branch_id');
  end if;
  if p_operation_id is null or p_operation_id !~ '^[A-Za-z0-9_-]{16,100}$' then
    return jsonb_build_object('ok',false,'error','invalid_operation_id');
  end if;
  if p_operation_type not in ('sale','collection','expense') or jsonb_typeof(p_payload) <> 'object' then
    return jsonb_build_object('ok',false,'error','invalid_operation');
  end if;
  payload_fingerprint := md5(p_operation_type || ':' || p_payload::text);
  perform pg_advisory_xact_lock(hashtextextended(p_branch_id || ':' || p_operation_id, 0));
  select * into prior from public.financial_operations where branch_id=p_branch_id and operation_id=p_operation_id;
  if found then
    if prior.payload_hash <> payload_fingerprint then
      return jsonb_build_object('ok',false,'conflict',true,'error','operation_id_reused_with_different_payload');
    end if;
    return prior.result || jsonb_build_object('replayed',true);
  end if;

  amount := round((p_payload->>'amountIqd')::numeric,2);
  paid := round(coalesce((p_payload->>'paidIqd')::numeric,0),2);
  remaining := round(coalesce((p_payload->>'remainingIqd')::numeric,greatest(amount-paid,0)),2);
  invoice_no := nullif(trim(p_payload->>'invoiceNo'),'');
  currency_value := coalesce(nullif(p_payload->>'currency',''),'IQD');
  details_value := coalesce(p_payload->'details','{}'::jsonb);
  if amount is null or amount <= 0 or paid < 0 or remaining < 0 or currency_value not in ('IQD','USD') then
    return jsonb_build_object('ok',false,'error','invalid_amount_or_currency');
  end if;
  if p_operation_type='sale' and (invoice_no is null or paid > amount or remaining <> amount-paid) then
    return jsonb_build_object('ok',false,'error','invalid_sale_invoice_or_totals');
  end if;
  if p_operation_type='collection' and (paid <> 0 or remaining <> 0) then
    -- Collection amount is the amount received; paidIqd/remainingIqd are not used.
    return jsonb_build_object('ok',false,'error','invalid_collection_totals');
  end if;
  if p_operation_type='expense' and (invoice_no is null or paid <> 0 or remaining <> 0) then
    return jsonb_build_object('ok',false,'error','invalid_expense_invoice_or_totals');
  end if;

  result_value := jsonb_build_object('ok',true,'branchId',p_branch_id,'operationId',p_operation_id,
    'operationType',p_operation_type,'invoiceNo',invoice_no,'amountIqd',amount,'replayed',false);
  begin
    insert into public.financial_operations(branch_id,operation_id,operation_type,payload_hash,payload,result)
      values(p_branch_id,p_operation_id,p_operation_type,payload_fingerprint,p_payload,result_value);
    if p_operation_type='sale' then
      if jsonb_typeof(details_value->'items') <> 'array' or jsonb_array_length(details_value->'items')=0 then
        raise exception using errcode='P0001', message='invalid_sale_items';
      end if;
      -- The row lock serializes sales for each product across all devices.
      for item_value in select value from jsonb_array_elements(details_value->'items') loop
        product_key := coalesce(item_value->>'id','');
        item_qty := (item_value->>'qty')::numeric;
        stock_before := (item_value->>'stockBefore')::numeric;
        if product_key='' or item_qty is null or item_qty<=0 or stock_before is null or stock_before<0 then
          raise exception using errcode='P0001', message='invalid_sale_items';
        end if;
        insert into public.branch_inventory_stock(branch_id,product_id,qty_on_hand)
          values(p_branch_id,product_key,stock_before) on conflict(branch_id,product_id) do nothing;
        select qty_on_hand into stock_current from public.branch_inventory_stock
          where branch_id=p_branch_id and product_id=product_key for update;
        if stock_current < item_qty then
          raise exception using errcode='P0001', message='insufficient_stock';
        end if;
        update public.branch_inventory_stock set qty_on_hand=qty_on_hand-item_qty,updated_at=now()
          where branch_id=p_branch_id and product_id=product_key returning qty_on_hand into stock_after;
        insert into public.inventory_stock_movements(branch_id,operation_id,product_id,qty_delta,qty_after,movement_type)
          values(p_branch_id,p_operation_id,product_key,-item_qty,stock_after,'sale');
      end loop;
    end if;
    if p_operation_type in ('sale','expense') then
      insert into public.financial_invoices(branch_id,operation_id,document_type,invoice_no,amount_iqd,paid_iqd,remaining_iqd,details)
        values(p_branch_id,p_operation_id,p_operation_type,invoice_no,amount,paid,remaining,details_value);
    end if;

    if p_operation_type='sale' then
      if paid > 0 then insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,1,'CASH',paid,0,'IQD','تحصيل فاتورة بيع'); end if;
      if remaining > 0 then insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,2,'ACCOUNTS_RECEIVABLE',remaining,0,'IQD','ذمم فاتورة بيع'); end if;
      insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,3,'SALES_REVENUE',0,amount,'IQD','إيراد فاتورة بيع');
    elsif p_operation_type='collection' then
      insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,1,'CASH',amount,0,'IQD','تحصيل دين عميل');
      insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,2,'ACCOUNTS_RECEIVABLE',0,amount,'IQD','تخفيض ذمم عميل');
    else
      insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,1,'OPERATING_EXPENSE',amount,0,'IQD','تسجيل مصروف');
      insert into public.accounting_entries(branch_id,operation_id,line_no,account_code,debit_iqd,credit_iqd,currency,memo)
        values(p_branch_id,p_operation_id,2,'CASH',0,amount,'IQD','صرف مصروف');
    end if;
  exception when unique_violation then
    -- Roll back this sub-block, then return a stable duplicate-document response.
    return jsonb_build_object('ok',false,'conflict',true,'error','duplicate_invoice_or_accounting_operation');
  when sqlstate 'P0001' then
    if sqlerrm='insufficient_stock' then
      return jsonb_build_object('ok',false,'conflict',true,'error','insufficient_stock');
    end if;
    return jsonb_build_object('ok',false,'conflict',true,'error',sqlerrm);
  end;
  return result_value;
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('ok',false,'error','invalid_numeric_payload');
end; $$;

revoke all on function public.record_financial_operation(text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.record_financial_operation(text,text,text,jsonb) to service_role;
