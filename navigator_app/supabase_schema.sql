-- =====================================================================
--  PickMe Taxi — схема Supabase
--  Выполните целиком в Supabase -> SQL Editor -> New query -> Run.
--  Скрипт можно запускать повторно.
--
--  ПЕРЕД ЗАПУСКОМ в Supabase -> Authentication -> Providers -> Email:
--  для разработки выключите "Confirm email" (иначе после регистрации
--  придётся подтверждать почту).
-- =====================================================================

-- ---------------------------------------------------------------- профили
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  role       text not null default 'client' check (role in ('client', 'driver')),
  full_name  text not null default '',
  phone      text not null default '',
  car_model  text,
  car_plate  text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Профиль создаётся автоматически при регистрации. Роль берётся из
-- metadata, которую передаёт приложение (client | driver).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r text := coalesce(new.raw_user_meta_data->>'role', 'client');
begin
  if r not in ('client', 'driver') then
    r := 'client';
  end if;
  insert into public.profiles (id, role, full_name, phone, car_model, car_plate)
  values (
    new.id,
    r,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'phone', ''),
    nullif(new.raw_user_meta_data->>'car_model', ''),
    nullif(new.raw_user_meta_data->>'car_plate', '')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Роль менять нельзя (иначе клиент мог бы сделать себя водителем).
create or replace function public.profiles_lock_role()
returns trigger
language plpgsql
as $$
begin
  if new.role <> old.role then
    raise exception 'role cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_lock_role on public.profiles;
create trigger profiles_lock_role
  before update on public.profiles
  for each row execute function public.profiles_lock_role();

-- Проверка "я водитель" без рекурсии в политиках (обходит RLS).
create or replace function public.is_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = auth.uid() and role = 'driver'
  );
$$;

-- ------------------------------------------------------------ позиции водителей
create table if not exists public.driver_locations (
  driver_id  uuid primary key references public.profiles(id) on delete cascade,
  lat        double precision not null,
  lon        double precision not null,
  is_online  boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.driver_locations enable row level security;

-- ----------------------------------------------------------------- заказы
create table if not exists public.rides (
  id             uuid primary key default gen_random_uuid(),
  client_id      uuid not null default auth.uid() references public.profiles(id),
  driver_id      uuid references public.profiles(id),
  status         text not null default 'searching' check (status in (
                   'searching', 'accepted', 'arrived', 'in_progress',
                   'completed', 'cancelled_by_client', 'cancelled_by_driver')),
  from_address   text not null,
  from_lat       double precision not null,
  from_lon       double precision not null,
  to_address     text not null,
  to_lat         double precision not null,
  to_lon         double precision not null,
  waypoints      jsonb not null default '[]'::jsonb,
  distance_m     integer not null check (distance_m >= 0),
  duration_s     integer not null check (duration_s >= 0),
  price          numeric(10, 2) not null default 0,
  payment_method text not null default 'cash' check (payment_method in ('cash', 'card')),
  payment_status text not null default 'pending' check (payment_status in ('pending', 'paid')),
  created_at     timestamptz not null default now(),
  accepted_at    timestamptz,
  started_at     timestamptz,
  completed_at   timestamptz
);

-- Не больше одного активного заказа у клиента и у водителя.
create unique index if not exists rides_one_active_per_client
  on public.rides (client_id)
  where status in ('searching', 'accepted', 'arrived', 'in_progress');

create unique index if not exists rides_one_active_per_driver
  on public.rides (driver_id)
  where status in ('accepted', 'arrived', 'in_progress');

alter table public.rides enable row level security;

-- Цену считает сервер, клиент повлиять на неё не может.
-- ТАРИФ ДОЛЖЕН СОВПАДАТЬ с Tariff в lib/config.dart:
-- подача 100 ₽ + 20 ₽/км + 5 ₽/мин, минимум 150 ₽, округление до 10 ₽.
create or replace function public.rides_before_insert()
returns trigger
language plpgsql
as $$
begin
  new.status := 'searching';
  new.driver_id := null;
  new.payment_status := 'pending';
  new.price := greatest(
    150,
    round((100 + 20 * (new.distance_m / 1000.0) + 5 * (new.duration_s / 60.0)) / 10) * 10
  );
  return new;
end;
$$;

drop trigger if exists rides_before_insert on public.rides;
create trigger rides_before_insert
  before insert on public.rides
  for each row execute function public.rides_before_insert();

-- ------------------------------------------------------------------ политики
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

-- Клиент видит профиль своего водителя, водитель — профиль своего клиента.
drop policy if exists profiles_select_counterparty on public.profiles;
create policy profiles_select_counterparty on public.profiles
  for select to authenticated using (
    exists (
      select 1 from public.rides r
      where r.status in ('accepted', 'arrived', 'in_progress', 'completed')
        and (
          (r.client_id = auth.uid() and r.driver_id = profiles.id)
          or (r.driver_id = auth.uid() and r.client_id = profiles.id)
        )
    )
  );

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists driver_locations_select on public.driver_locations;
create policy driver_locations_select on public.driver_locations
  for select to authenticated using (
    driver_id = auth.uid()
    or exists (
      select 1 from public.rides r
      where r.driver_id = driver_locations.driver_id
        and r.client_id = auth.uid()
        and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

drop policy if exists driver_locations_insert on public.driver_locations;
create policy driver_locations_insert on public.driver_locations
  for insert to authenticated
  with check (driver_id = auth.uid() and public.is_driver());

drop policy if exists driver_locations_update on public.driver_locations;
create policy driver_locations_update on public.driver_locations
  for update to authenticated
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

-- Заказ видят: его клиент, назначенный водитель и (пока идёт поиск) все водители.
drop policy if exists rides_select on public.rides;
create policy rides_select on public.rides
  for select to authenticated using (
    client_id = auth.uid()
    or driver_id = auth.uid()
    or (status = 'searching' and public.is_driver())
  );

-- Создавать заказ может только клиент и только от своего имени.
-- UPDATE/DELETE напрямую запрещены — статусы меняются функциями ниже.
drop policy if exists rides_insert on public.rides;
create policy rides_insert on public.rides
  for insert to authenticated
  with check (client_id = auth.uid() and not public.is_driver());

-- ------------------------------------------------------- функции (RPC)
-- Водитель берёт заказ. true — получилось, false — уже занят.
create or replace function public.accept_ride(p_ride_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if auth.uid() is null or not public.is_driver() then
    raise exception 'only drivers can accept rides';
  end if;

  update public.rides
     set driver_id = auth.uid(), status = 'accepted', accepted_at = now()
   where id = p_ride_id and status = 'searching' and driver_id is null;
  get diagnostics n = row_count;
  return n = 1;
exception
  when unique_violation then
    -- у водителя уже есть активный заказ
    return false;
end;
$$;

-- Водитель двигает заказ вперёд: accepted -> arrived -> in_progress -> completed.
-- Наличные считаются оплаченными в момент завершения.
create or replace function public.advance_ride(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.rides
     set status = case status
                    when 'accepted'    then 'arrived'
                    when 'arrived'     then 'in_progress'
                    when 'in_progress' then 'completed'
                  end,
         started_at = case when status = 'arrived' then now() else started_at end,
         completed_at = case when status = 'in_progress' then now() else completed_at end,
         payment_status = case
                            when status = 'in_progress' and payment_method = 'cash'
                              then 'paid'
                            else payment_status
                          end
   where id = p_ride_id
     and driver_id = auth.uid()
     and status in ('accepted', 'arrived', 'in_progress');
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'ride cannot be advanced';
  end if;
end;
$$;

-- Водитель отказывается: заказ возвращается в поиск.
create or replace function public.release_ride(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.rides
     set driver_id = null, status = 'searching', accepted_at = null
   where id = p_ride_id
     and driver_id = auth.uid()
     and status in ('accepted', 'arrived');
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'ride cannot be released';
  end if;
end;
$$;

-- Клиент отменяет заказ (пока поездка не началась).
create or replace function public.cancel_ride(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  update public.rides
     set status = 'cancelled_by_client'
   where id = p_ride_id
     and client_id = auth.uid()
     and status in ('searching', 'accepted', 'arrived');
  get diagnostics n = row_count;
  if n <> 1 then
    raise exception 'ride cannot be cancelled';
  end if;
end;
$$;

-- ТЕСТОВАЯ оплата картой (заглушка в приложении).
-- В проде уберите эту функцию: оплату должен подтверждать платёжный
-- провайдер через webhook -> Edge Function, а не приложение.
create or replace function public.mark_ride_paid(p_ride_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.rides
     set payment_status = 'paid'
   where id = p_ride_id
     and client_id = auth.uid()
     and status = 'completed'
     and payment_method = 'card';
end;
$$;

revoke all on function public.accept_ride(uuid)    from public, anon;
revoke all on function public.advance_ride(uuid)   from public, anon;
revoke all on function public.release_ride(uuid)   from public, anon;
revoke all on function public.cancel_ride(uuid)    from public, anon;
revoke all on function public.mark_ride_paid(uuid) from public, anon;
grant execute on function public.accept_ride(uuid)    to authenticated;
grant execute on function public.advance_ride(uuid)   to authenticated;
grant execute on function public.release_ride(uuid)   to authenticated;
grant execute on function public.cancel_ride(uuid)    to authenticated;
grant execute on function public.mark_ride_paid(uuid) to authenticated;

-- -------------------------------------------------- закладки/история клиента
create table if not exists public.bookmarks (
  id         bigint generated always as identity primary key,
  address    text not null,
  latitude   double precision not null,
  longitude  double precision not null,
  type       text not null check (type in ('bookmark', 'history', 'home', 'work')),
  created_at timestamptz not null default now()
);

alter table public.bookmarks
  add column if not exists user_id uuid default auth.uid()
  references auth.users(id) on delete cascade;

alter table public.bookmarks enable row level security;

-- Старая открытая политика из версии без авторизации.
drop policy if exists "anon full access" on public.bookmarks;
drop policy if exists "own bookmarks" on public.bookmarks;
create policy "own bookmarks" on public.bookmarks
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ------------------------------------------------------------- Realtime
alter table public.rides replica identity full;
alter table public.driver_locations replica identity full;

do $$
begin
  begin
    alter publication supabase_realtime add table public.rides;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.driver_locations;
  exception when duplicate_object then null;
  end;
end;
$$;
