-- Ejecutar una vez en Supabase SQL Editor.
-- Administración privada y reversible de los jugadores.
alter table public.jugadores
  add column if not exists activo boolean not null default true,
  add column if not exists bloqueado boolean not null default false;

create or replace function public.usuario_actual_es_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.jugadores
     where lower(email) = lower((select auth.jwt() ->> 'email'))
       and es_admin = true and activo = true and bloqueado = false
  );
$$;

create or replace function public.listar_jugadores_publicos()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'alias', alias, 'foto_path', foto_path, 'activo', true, 'bloqueado', false
  ) order by lower(alias)), '[]'::jsonb)
  from public.jugadores where activo = true;
$$;

create or replace function public.listar_jugadores_gestion()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.usuario_actual_es_admin() then
    raise exception 'Solo el administrador puede gestionar jugadores';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'alias', alias, 'foto_path', foto_path,
      'activo', activo, 'bloqueado', bloqueado,
      'es_actual', lower(email) = lower((select auth.jwt() ->> 'email'))
    ) order by activo desc, lower(alias)), '[]'::jsonb)
    from public.jugadores
  );
end;
$$;

create or replace function public.administrar_jugador(
  objetivo_id text, accion text, nuevo_alias text default null
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  admin_id text;
  alias_limpio text := regexp_replace(btrim(coalesce(nuevo_alias, '')), '\s+', ' ', 'g');
begin
  select id::text into admin_id from public.jugadores
   where lower(email) = lower((select auth.jwt() ->> 'email'))
     and es_admin = true and activo = true and bloqueado = false;
  if admin_id is null then raise exception 'Solo el administrador puede gestionar jugadores'; end if;
  if not exists (select 1 from public.jugadores where id::text = objetivo_id) then
    raise exception 'Jugador inexistente';
  end if;
  if objetivo_id = admin_id and accion in ('bloquear', 'retirar') then
    raise exception 'El administrador debe primero ceder la administración';
  end if;

  if accion = 'editar' then
    if char_length(alias_limpio) < 2 or char_length(alias_limpio) > 40 then
      raise exception 'El nombre debe tener entre 2 y 40 caracteres';
    end if;
    if exists (select 1 from public.jugadores where lower(btrim(alias)) = lower(alias_limpio) and id::text <> objetivo_id) then
      raise exception 'Ese nombre ya está en uso';
    end if;
    update public.jugadores set alias = alias_limpio where id::text = objetivo_id;
  elsif accion = 'bloquear' then
    update public.jugadores set bloqueado = true where id::text = objetivo_id;
    delete from public.inscripciones i using public.partidos p
     where i.partido_id = p.id and p.estado = 'abierto'
       and i.jugador_id in (select id from public.jugadores where id::text = objetivo_id);
  elsif accion = 'desbloquear' then
    update public.jugadores set bloqueado = false where id::text = objetivo_id and activo = true;
  elsif accion = 'retirar' then
    update public.jugadores set activo = false, bloqueado = true where id::text = objetivo_id;
    delete from public.inscripciones i using public.partidos p
     where i.partido_id = p.id and p.estado = 'abierto'
       and i.jugador_id in (select id from public.jugadores where id::text = objetivo_id);
  elsif accion = 'reactivar' then
    update public.jugadores set activo = true, bloqueado = false where id::text = objetivo_id;
  else
    raise exception 'Acción inválida';
  end if;
end;
$$;

create or replace function public.transferir_administracion(nuevo_admin_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  admin_id text;
begin
  select id::text into admin_id from public.jugadores
   where lower(email) = lower((select auth.jwt() ->> 'email'))
     and es_admin = true and activo = true and bloqueado = false;
  if admin_id is null then raise exception 'Solo el administrador puede ceder la administración'; end if;
  if nuevo_admin_id = admin_id then raise exception 'Ya sos el administrador'; end if;
  if not exists (select 1 from public.jugadores where id::text = nuevo_admin_id and activo = true and bloqueado = false) then
    raise exception 'El nuevo administrador debe ser un jugador activo';
  end if;

  update public.jugadores set es_admin = false where es_admin = true;
  update public.jugadores set es_admin = true where id::text = nuevo_admin_id;
end;
$$;

drop policy if exists "Solo jugadores habilitados se anotan" on public.inscripciones;
create policy "Solo jugadores habilitados se anotan" on public.inscripciones
  as restrictive for insert to authenticated
  with check (exists (
    select 1 from public.jugadores
     where lower(email) = lower((select auth.jwt() ->> 'email'))
       and activo = true and bloqueado = false
  ));

drop policy if exists "Solo jugadores habilitados agregan invitados" on public.invitados;
create policy "Solo jugadores habilitados agregan invitados" on public.invitados
  as restrictive for insert to authenticated
  with check (exists (
    select 1 from public.jugadores
     where lower(email) = lower((select auth.jwt() ->> 'email'))
       and activo = true and bloqueado = false
  ));

revoke all on function public.usuario_actual_es_admin() from public;
revoke all on function public.listar_jugadores_publicos() from public;
revoke all on function public.listar_jugadores_gestion() from public;
revoke all on function public.administrar_jugador(text, text, text) from public;
revoke all on function public.transferir_administracion(text) from public;
grant execute on function public.usuario_actual_es_admin() to anon, authenticated;
grant execute on function public.listar_jugadores_publicos() to anon, authenticated;
grant execute on function public.listar_jugadores_gestion() to authenticated;
grant execute on function public.administrar_jugador(text, text, text) to authenticated;
grant execute on function public.transferir_administracion(text) to authenticated;
