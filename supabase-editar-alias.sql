-- Ejecutar una vez en Supabase SQL Editor.
-- Permite que cada jugador cambie solamente su propio alias.
create or replace function public.actualizar_alias_perfil(nuevo_alias text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  usuario_email text := (select auth.jwt() ->> 'email');
  alias_limpio text := regexp_replace(btrim(coalesce(nuevo_alias, '')), '\s+', ' ', 'g');
begin
  if usuario_email is null then
    raise exception 'Primero tenés que iniciar sesión';
  end if;

  if char_length(alias_limpio) < 2 or char_length(alias_limpio) > 40 then
    raise exception 'El nombre debe tener entre 2 y 40 caracteres';
  end if;

  if exists (
    select 1 from public.jugadores
     where lower(btrim(alias)) = lower(alias_limpio)
       and lower(email) <> lower(usuario_email)
  ) then
    raise exception 'Ese nombre ya está en uso';
  end if;

  update public.jugadores
     set alias = alias_limpio
   where lower(email) = lower(usuario_email);

  if not found then
    raise exception 'Tu cuenta todavía no figura en la lista de jugadores';
  end if;

  return alias_limpio;
end;
$$;

revoke all on function public.actualizar_alias_perfil(text) from public;
grant execute on function public.actualizar_alias_perfil(text) to authenticated;
