-- Ejecutar una sola vez en el SQL Editor de Supabase.
create table if not exists public.invitados (
  id bigint generated always as identity primary key,
  partido_id bigint not null references public.partidos(id),
  alias text not null check (length(btrim(alias)) between 2 and 40),
  agregado_por uuid not null,
  estado text not null default 'suplente' check (estado in ('titular', 'suplente')),
  equipo text check (equipo in ('A', 'B')),
  created_at timestamptz not null default now()
);

create unique index if not exists invitados_partido_alias_unique
  on public.invitados (partido_id, lower(btrim(alias)));

create index if not exists invitados_partido_idx
  on public.invitados (partido_id);

alter table public.invitados enable row level security;
grant select on public.invitados to anon, authenticated;
grant insert, delete, update on public.invitados to authenticated;

drop policy if exists "Ver invitados del partido" on public.invitados;
create policy "Ver invitados del partido" on public.invitados
  for select to anon, authenticated using (true);

drop policy if exists "Agregar invitados propios" on public.invitados;
create policy "Agregar invitados propios" on public.invitados
  for insert to authenticated
  with check (
    agregado_por = (select auth.uid())
    and exists (
      select 1 from public.jugadores
      where jugadores.email = (select auth.jwt() ->> 'email')
    )
    and exists (
      select 1 from public.partidos
      where partidos.id = partido_id and partidos.estado = 'abierto'
    )
  );

drop policy if exists "Quitar invitados propios" on public.invitados;
create policy "Quitar invitados propios" on public.invitados
  for delete to authenticated
  using (
    agregado_por = (select auth.uid())
    and exists (
      select 1 from public.partidos
      where partidos.id = partido_id and partidos.estado = 'abierto'
    )
  );

drop policy if exists "Admin organiza invitados" on public.invitados;
create policy "Admin organiza invitados" on public.invitados
  for update to authenticated
  using (
    exists (
      select 1 from public.jugadores
      where jugadores.email = (select auth.jwt() ->> 'email')
        and jugadores.es_admin = true
    )
    and exists (
      select 1 from public.partidos
      where partidos.id = partido_id and partidos.estado = 'abierto'
    )
  )
  with check (
    exists (
      select 1 from public.jugadores
      where jugadores.email = (select auth.jwt() ->> 'email')
        and jugadores.es_admin = true
    )
  );

-- Una misma traba por partido evita que dos altas simultáneas ocupen el lugar 14.
create or replace function public.asignar_cupo_partido()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  titulares_actuales integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(new.partido_id);

  if not exists (
    select 1 from public.partidos
    where id = new.partido_id and estado = 'abierto'
  ) then
    raise exception 'El partido ya no está abierto';
  end if;

  select (select count(*) from public.inscripciones
          where partido_id = new.partido_id and estado = 'titular')
       + (select count(*) from public.invitados
          where partido_id = new.partido_id and estado = 'titular')
    into titulares_actuales;

  new.estado := case when titulares_actuales < 14 then 'titular' else 'suplente' end;

  if tg_table_name = 'invitados' then
    new.alias := btrim(new.alias);
    new.equipo := null;
  end if;

  return new;
end;
$$;

drop trigger if exists asignar_cupo_invitados on public.invitados;
create trigger asignar_cupo_invitados
  before insert on public.invitados for each row
  execute function public.asignar_cupo_partido();

drop trigger if exists asignar_cupo_inscripciones on public.inscripciones;
create trigger asignar_cupo_inscripciones
  before insert on public.inscripciones for each row
  execute function public.asignar_cupo_partido();

-- Si cambia un titular después del sorteo, el administrador debe volver a confirmarlo.
create or replace function public.revisar_sorteo_al_cambiar_titular()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    if old.estado = 'titular' then
      update public.partidos set sorteo_confirmado = false where id = old.partido_id;
    end if;
    return old;
  end if;
  if new.estado = 'titular' then
    update public.partidos set sorteo_confirmado = false where id = new.partido_id;
  end if;
  return new;
end;
$$;

drop trigger if exists revisar_sorteo_invitados on public.invitados;
create trigger revisar_sorteo_invitados
  after insert or delete on public.invitados for each row
  execute function public.revisar_sorteo_al_cambiar_titular();

drop trigger if exists revisar_sorteo_inscripciones on public.inscripciones;
create trigger revisar_sorteo_inscripciones
  after insert or delete on public.inscripciones for each row
  execute function public.revisar_sorteo_al_cambiar_titular();
