-- Nesto 1.3 · Proyecto nuevo: iqhvuujmpprnzzgzcvwm
-- Ejecutar completo en Supabase > SQL Editor > New query > Run.
-- No borra tablas ni registros. Repetible sobre el esquema de Nesto.
begin;

create table if not exists public.finance_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  currency text not null default 'DOP' check (currency in ('DOP','USD','EUR')),
  categories jsonb not null default '["Otros"]'::jsonb check (jsonb_typeof(categories)='array'),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items)='array'),
  goals jsonb not null default '[]'::jsonb check (jsonb_typeof(goals)='array'),
  goals_revision bigint not null default 0 check (goals_revision>=0)
);
alter table public.finance_settings add column if not exists goals jsonb not null default '[]'::jsonb;
alter table public.finance_settings add column if not exists goals_revision bigint not null default 0;

create table if not exists public.finance_months (
  user_id uuid not null references auth.users(id) on delete cascade,
  month text not null check (month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  items jsonb not null default '[]'::jsonb check (jsonb_typeof(items)='array'),
  primary key (user_id,month)
);

create table if not exists public.wealth_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{"portfolios":[],"investments":[],"movements":[],"savings":[],"fx":60}'::jsonb,
  revision bigint not null default 0 check (revision>=0),
  updated_at timestamptz not null default now(),
  constraint nesto_wealth_payload_object check (jsonb_typeof(payload)='object'),
  constraint nesto_wealth_payload_size check (octet_length(payload::text)<=5242880)
);

-- Solo el usuario autenticado puede leer o modificar su propia fila.
-- Una política restrictiva evita que otra política permisiva amplíe el acceso.
do $policies$
declare target text;
begin
  foreach target in array array['finance_settings','finance_months','wealth_accounts'] loop
    execute format('alter table public.%I enable row level security',target);
    execute format('revoke all on table public.%I from public, anon',target);
    execute format('revoke all on table public.%I from authenticated',target);
    execute format('grant select, insert, update on table public.%I to authenticated',target);
    execute format('drop policy if exists nesto_owner_select on public.%I',target);
    execute format('drop policy if exists nesto_owner_insert on public.%I',target);
    execute format('drop policy if exists nesto_owner_update on public.%I',target);
    execute format('drop policy if exists nesto_owner_boundary on public.%I',target);
    execute format('create policy nesto_owner_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)',target);
    execute format('create policy nesto_owner_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)',target);
    execute format('create policy nesto_owner_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',target);
    execute format('create policy nesto_owner_boundary on public.%I as restrictive for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)',target);
  end loop;
end;
$policies$;

-- Guardado atómico de patrimonio con revisión: no pisa cambios de otro dispositivo.
-- SECURITY INVOKER mantiene las políticas RLS del usuario que realiza la llamada.
create or replace function public.save_nesto_wealth(p_payload jsonb,p_expected_revision bigint)
returns bigint
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  owner_id uuid := auth.uid();
  current_revision bigint;
  next_revision bigint;
  array_name text;
begin
  if owner_id is null then
    raise exception 'NESTO_AUTH_REQUIRED' using errcode='42501';
  end if;
  if p_expected_revision is null or p_expected_revision<0 then
    raise exception 'NESTO_INVALID_REVISION' using errcode='22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>5242880 then
    raise exception 'NESTO_INVALID_PAYLOAD' using errcode='22023';
  end if;
  foreach array_name in array array['portfolios','investments','movements','savings'] loop
    if coalesce(jsonb_typeof(p_payload->array_name),'null')<>'array' then
      raise exception 'NESTO_INVALID_ARRAY' using errcode='22023';
    end if;
  end loop;
  if coalesce(jsonb_typeof(p_payload->'fx'),'null')<>'number' then
    raise exception 'NESTO_INVALID_FX' using errcode='22023';
  end if;
  if (p_payload->>'fx')::numeric<=0 then
    raise exception 'NESTO_INVALID_FX' using errcode='22023';
  end if;
  insert into public.wealth_accounts(user_id) values(owner_id) on conflict(user_id) do nothing;
  select revision into current_revision from public.wealth_accounts where user_id=owner_id for update;
  if current_revision is distinct from p_expected_revision then
    raise exception 'NESTO_WEALTH_CONFLICT' using errcode='40001';
  end if;
  update public.wealth_accounts set payload=p_payload,revision=revision+1,updated_at=now()
    where user_id=owner_id returning revision into next_revision;
  return next_revision;
end;
$function$;
revoke all on function public.save_nesto_wealth(jsonb,bigint) from public,anon;
grant execute on function public.save_nesto_wealth(jsonb,bigint) to authenticated;
notify pgrst,'reload schema';
commit;

-- Resultado esperado: tres filas con rls_activo = true.
select c.relname as tabla,c.relrowsecurity as rls_activo
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in ('finance_settings','finance_months','wealth_accounts')
order by c.relname;
