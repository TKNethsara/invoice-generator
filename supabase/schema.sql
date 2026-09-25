-- InvoicePro Supabase schema
-- Run this in Supabase SQL Editor.
-- IMPORTANT: user_roles is intentionally not writable by normal users.

create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('user','admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.account_status as enum ('active','disabled');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  business_name text,
  email text,
  phone text,
  address text,
  website text,
  tax_number text,
  logo_url text,
  account_status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  role public.app_role not null default 'user',
  created_at timestamptz not null default now()
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  company_name text,
  email text,
  phone text,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  description text,
  price numeric(14,2) not null default 0 check (price >= 0),
  tax_rate numeric(7,3) not null default 0 check (tax_rate >= 0),
  unit text not null default 'unit',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete restrict,
  invoice_number text not null,
  invoice_date date not null default current_date,
  due_date date not null,
  currency text not null default 'LKR' check (currency in ('LKR','USD','EUR','GBP','INR','AUD','CAD')),
  status text not null default 'draft' check (status in ('draft','pending','paid','overdue','cancelled')),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  tax numeric(14,2) not null default 0 check (tax >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  notes text,
  payment_terms text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, invoice_number)
);

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  product_id uuid null references public.products(id) on delete set null,
  description text,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  discount numeric(7,3) not null default 0 check (discount >= 0),
  tax_rate numeric(7,3) not null default 0 check (tax_rate >= 0),
  tax_amount numeric(14,2) not null default 0 check (tax_amount >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  invoice_prefix text not null default 'INV',
  next_invoice_number integer not null default 1 check (next_invoice_number > 0),
  default_currency text not null default 'LKR' check (default_currency in ('LKR','USD','EUR','GBP','INR','AUD','CAD')),
  default_tax_rate numeric(7,3) not null default 0 check (default_tax_rate >= 0),
  default_payment_terms text not null default 'Due on receipt',
  theme text not null default 'light' check (theme in ('light','dark')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  target_user_id uuid null references auth.users(id) on delete set null,
  target_record_id uuid null,
  description text,
  created_at timestamptz not null default now()
);

-- Keep ownership defaults correct even when this schema is applied to an existing project.
alter table public.customers alter column user_id set default auth.uid();
alter table public.products alter column user_id set default auth.uid();
alter table public.invoices alter column user_id set default auth.uid();

create index if not exists customers_user_id_idx on public.customers(user_id);
create index if not exists products_user_id_idx on public.products(user_id);
create index if not exists invoices_user_id_idx on public.invoices(user_id);
create index if not exists invoices_customer_id_idx on public.invoices(customer_id);
create index if not exists invoices_status_idx on public.invoices(status);
create index if not exists invoices_date_idx on public.invoices(invoice_date desc);
create index if not exists invoice_items_invoice_id_idx on public.invoice_items(invoice_id);
create index if not exists invoice_items_product_id_idx on public.invoice_items(product_id);
create index if not exists user_roles_role_idx on public.user_roles(role);
create index if not exists audit_admin_idx on public.admin_audit_logs(admin_user_id);
create index if not exists audit_target_idx on public.admin_audit_logs(target_user_id);

-- Timestamp helper.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists customers_updated_at on public.customers;
create trigger customers_updated_at before update on public.customers for each row execute function public.set_updated_at();
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products for each row execute function public.set_updated_at();
drop trigger if exists invoices_updated_at on public.invoices;
create trigger invoices_updated_at before update on public.invoices for each row execute function public.set_updated_at();
drop trigger if exists settings_updated_at on public.settings;
create trigger settings_updated_at before update on public.settings for each row execute function public.set_updated_at();

-- Automatically create profile/settings/normal role after Auth signup.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, business_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    coalesce(new.raw_user_meta_data->>'business_name',''),
    new.email
  )
  on conflict (id) do nothing;

  insert into public.user_roles(user_id, role)
  values (new.id, 'user')
  on conflict (user_id) do nothing;

  insert into public.settings(user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- SECURITY DEFINER role check. It is not client-writable.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

-- Keep roles server-controlled. There is deliberately no INSERT/UPDATE/DELETE grant/policy
-- for authenticated users on user_roles.
alter table public.user_roles enable row level security;
drop policy if exists "roles self read" on public.user_roles;
create policy "roles self read" on public.user_roles
for select to authenticated
using (user_id = auth.uid() or (select public.is_admin()));

-- Prevent normal users from changing security-sensitive profile fields.
create or replace function public.protect_profile_security_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() <> old.id then
    raise exception 'Profile ownership violation';
  end if;
  if not public.is_admin() then
    new.id := old.id;
    new.account_status := old.account_status;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_profile_security_fields() from public;
grant execute on function public.protect_profile_security_fields() to authenticated;
drop trigger if exists profiles_security_guard on public.profiles;
create trigger profiles_security_guard
before update on public.profiles
for each row execute function public.protect_profile_security_fields();

-- Profiles
alter table public.profiles enable row level security;
drop policy if exists "profiles self select" on public.profiles;
create policy "profiles self select" on public.profiles for select to authenticated
using (id = auth.uid() or (select public.is_admin()));
drop policy if exists "profiles self insert" on public.profiles;
create policy "profiles self insert" on public.profiles for insert to authenticated
with check (id = auth.uid());
drop policy if exists "profiles self update" on public.profiles;
create policy "profiles self update" on public.profiles for update to authenticated
using (id = auth.uid() or (select public.is_admin()))
with check (id = auth.uid() or (select public.is_admin()));
drop policy if exists "profiles self delete" on public.profiles;
create policy "profiles self delete" on public.profiles for delete to authenticated
using (id = auth.uid() or (select public.is_admin()));

-- Customers
alter table public.customers enable row level security;
drop policy if exists "customers own select" on public.customers;
create policy "customers own select" on public.customers for select to authenticated
using (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "customers own insert" on public.customers;
create policy "customers own insert" on public.customers for insert to authenticated
with check (user_id = auth.uid());
drop policy if exists "customers own update" on public.customers;
create policy "customers own update" on public.customers for update to authenticated
using (user_id = auth.uid() or (select public.is_admin()))
with check (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "customers own delete" on public.customers;
create policy "customers own delete" on public.customers for delete to authenticated
using (user_id = auth.uid() or (select public.is_admin()));

-- Products
alter table public.products enable row level security;
drop policy if exists "products own select" on public.products;
create policy "products own select" on public.products for select to authenticated
using (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "products own insert" on public.products;
create policy "products own insert" on public.products for insert to authenticated
with check (user_id = auth.uid());
drop policy if exists "products own update" on public.products;
create policy "products own update" on public.products for update to authenticated
using (user_id = auth.uid() or (select public.is_admin()))
with check (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "products own delete" on public.products;
create policy "products own delete" on public.products for delete to authenticated
using (user_id = auth.uid() or (select public.is_admin()));

-- Invoices
alter table public.invoices enable row level security;
drop policy if exists "invoices own select" on public.invoices;
create policy "invoices own select" on public.invoices for select to authenticated
using (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "invoices own insert" on public.invoices;
create policy "invoices own insert" on public.invoices for insert to authenticated
with check (user_id = auth.uid());
drop policy if exists "invoices own update" on public.invoices;
create policy "invoices own update" on public.invoices for update to authenticated
using (user_id = auth.uid() or (select public.is_admin()))
with check (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "invoices own delete" on public.invoices;
create policy "invoices own delete" on public.invoices for delete to authenticated
using (user_id = auth.uid() or (select public.is_admin()));

-- Invoice items: ownership is derived from parent invoice.
alter table public.invoice_items enable row level security;
drop policy if exists "items parent invoice select" on public.invoice_items;
create policy "items parent invoice select" on public.invoice_items for select to authenticated
using (exists(select 1 from public.invoices i where i.id=invoice_id and (i.user_id=auth.uid() or (select public.is_admin()))));
drop policy if exists "items parent invoice insert" on public.invoice_items;
create policy "items parent invoice insert" on public.invoice_items for insert to authenticated
with check (exists(select 1 from public.invoices i where i.id=invoice_id and (i.user_id=auth.uid() or (select public.is_admin()))));
drop policy if exists "items parent invoice update" on public.invoice_items;
create policy "items parent invoice update" on public.invoice_items for update to authenticated
using (exists(select 1 from public.invoices i where i.id=invoice_id and (i.user_id=auth.uid() or (select public.is_admin()))))
with check (exists(select 1 from public.invoices i where i.id=invoice_id and (i.user_id=auth.uid() or (select public.is_admin()))));
drop policy if exists "items parent invoice delete" on public.invoice_items;
create policy "items parent invoice delete" on public.invoice_items for delete to authenticated
using (exists(select 1 from public.invoices i where i.id=invoice_id and (i.user_id=auth.uid() or (select public.is_admin()))));

-- Settings
alter table public.settings enable row level security;
drop policy if exists "settings own select" on public.settings;
create policy "settings own select" on public.settings for select to authenticated
using (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "settings own insert" on public.settings;
create policy "settings own insert" on public.settings for insert to authenticated
with check (user_id = auth.uid());
drop policy if exists "settings own update" on public.settings;
create policy "settings own update" on public.settings for update to authenticated
using (user_id = auth.uid() or (select public.is_admin()))
with check (user_id = auth.uid() or (select public.is_admin()));
drop policy if exists "settings own delete" on public.settings;
create policy "settings own delete" on public.settings for delete to authenticated
using (user_id = auth.uid() or (select public.is_admin()));

-- Enforce cross-table ownership for invoice/customer/product relationships.
create or replace function public.enforce_invoice_relationship_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  invoice_owner uuid;
  customer_owner uuid;
  product_owner uuid;
begin
  if tg_table_name = 'invoices' then
    select user_id into customer_owner from public.customers where id = new.customer_id;
    if customer_owner is null or customer_owner <> new.user_id then
      raise exception 'Customer ownership violation';
    end if;
    return new;
  end if;

  select user_id into invoice_owner from public.invoices where id = new.invoice_id;
  if invoice_owner is null then raise exception 'Invoice not found'; end if;

  if new.product_id is not null then
    select user_id into product_owner from public.products where id = new.product_id;
    if product_owner is null or product_owner <> invoice_owner then
      raise exception 'Product ownership violation';
    end if;
  end if;
  return new;
end;
$$;

-- Invoice ownership is checked when creating/updating invoices.
drop trigger if exists invoices_relationship_guard on public.invoices;
create trigger invoices_relationship_guard
before insert or update on public.invoices
for each row execute function public.enforce_invoice_relationship_ownership();

-- Item product ownership is checked against the parent invoice.
drop trigger if exists invoice_items_relationship_guard on public.invoice_items;
create trigger invoice_items_relationship_guard
before insert or update on public.invoice_items
for each row execute function public.enforce_invoice_relationship_ownership();

revoke all on function public.enforce_invoice_relationship_ownership() from public;
grant execute on function public.enforce_invoice_relationship_ownership() to authenticated;

-- Audit logs: only admins can read. Inserts happen through SECURITY DEFINER admin RPCs.
alter table public.admin_audit_logs enable row level security;
drop policy if exists "audit admin select" on public.admin_audit_logs;
create policy "audit admin select" on public.admin_audit_logs for select to authenticated
using ((select public.is_admin()));

-- Admin account status RPC.
create or replace function public.admin_set_account_status(target_user_id uuid, new_status public.account_status)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'Admin access required'; end if;
  if target_user_id = auth.uid() then raise exception 'Cannot change your own status'; end if;
  update public.profiles set account_status = new_status where id = target_user_id;
  insert into public.admin_audit_logs(admin_user_id,action,target_user_id,description)
  values(auth.uid(),case when new_status='active' then 'user_enabled' else 'user_disabled' end,target_user_id,
         'Account status changed to '||new_status::text);
  return true;
end $$;

revoke all on function public.admin_set_account_status(uuid,public.account_status) from public;
grant execute on function public.admin_set_account_status(uuid,public.account_status) to authenticated;

-- Admin overview view. It exposes only fields needed by the admin UI.
create or replace view public.admin_user_overview
with (security_invoker=true)
as
select
  p.id,
  p.full_name,
  p.business_name,
  p.email,
  p.created_at,
  p.account_status,
  count(distinct i.id)::bigint as total_invoices,
  count(distinct i.id) filter (where i.status='paid')::bigint as paid_invoices,
  count(distinct i.id) filter (where i.status='pending')::bigint as pending_invoices,
  count(distinct i.id) filter (where i.status='overdue')::bigint as overdue_invoices,
  coalesce(sum(i.total) filter (where i.status='paid'),0)::numeric as total_revenue,
  coalesce(sum(i.total) filter (where i.status in ('pending','overdue','draft')),0)::numeric as pending_revenue
from public.profiles p
left join public.invoices i on i.user_id=p.id
where public.is_admin()
group by p.id;

-- Least-privilege Data API grants.
grant select, insert, update, delete on public.profiles, public.customers, public.products,
  public.invoices, public.invoice_items, public.settings to authenticated;
revoke all on public.user_roles from authenticated;
grant select on public.user_roles to authenticated;
revoke all on public.admin_audit_logs from authenticated;
grant select on public.admin_user_overview to authenticated;

-- Storage bucket and policies.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('business-logos','business-logos',false,6291456,array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public=false, file_size_limit=6291456,
allowed_mime_types=array['image/png','image/jpeg','image/webp'];

drop policy if exists "logo select own" on storage.objects;
create policy "logo select own" on storage.objects for select to authenticated
using (bucket_id='business-logos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "logo insert own" on storage.objects;
create policy "logo insert own" on storage.objects for insert to authenticated
with check (bucket_id='business-logos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "logo update own" on storage.objects;
create policy "logo update own" on storage.objects for update to authenticated
using (bucket_id='business-logos' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='business-logos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "logo delete own" on storage.objects;
create policy "logo delete own" on storage.objects for delete to authenticated
using (bucket_id='business-logos' and (storage.foldername(name))[1]=auth.uid()::text);

-- SECURITY NOTE:
-- Do not grant authenticated access to modify user_roles.
-- Do not expose service_role in browser code.
-- Promote the first admin only from the SQL editor, or through a trusted server-side operation.
