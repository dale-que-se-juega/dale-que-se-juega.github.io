-- Ejecutar una sola vez en Supabase SQL Editor.
-- Crea la ficha de jugador del usuario autenticado si todavía no existe.
create or replace function public.asegurar_perfil_jugador()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  usuario_id uuid := (select auth.uid());
  usuario_email text := lower(btrim((select auth.jwt() ->> 'email')));
  alias_base text;
  alias_final text;
  jugador_id text;
begin
  if usuario_id is null or usuario_email is null or usuario_email = '' then
    raise exception 'Primero tenés que iniciar sesión';
  end if;

  select id::text into jugador_id
    from public.jugadores
   where lower(email) = usuario_email
   limit 1;

  if jugador_id is not null then
    return jsonb_build_object('id', jugador_id, 'creado', false);
  end if;

  alias_base := regexp_replace(split_part(usuario_email, '@', 1), '[._-]+', ' ', 'g');
  alias_base := regexp_replace(btrim(alias_base), '\s+', ' ', 'g');
  if char_length(alias_base) < 2 then
    alias_base := 'Jugador';
  end if;
  alias_base := left(alias_base, 40);
  alias_final := alias_base;

  if exists (
    select 1 from public.jugadores
     where lower(btrim(alias)) = lower(alias_final)
  ) then
    alias_final := left(alias_base, 31) || '-' || substr(usuario_id::text, 1, 8);
  end if;

  insert into public.jugadores (alias, email, es_admin, activo, bloqueado)
  values (alias_final, usuario_email, false, true, false)
  returning id::text into jugador_id;

  return jsonb_build_object('id', jugador_id, 'creado', true);
end;
$$;

revoke all on function public.asegurar_perfil_jugador() from public;
grant execute on function public.asegurar_perfil_jugador() to authenticated;
