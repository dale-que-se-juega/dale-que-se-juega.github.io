-- Ejecutar en SQL Editor antes de publicar la interfaz de fotos.
-- Las fotos son visibles para quienes abran la app; cada jugador solo puede subir la suya.
alter table public.jugadores
  add column if not exists foto_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('jugadores-fotos', 'jugadores-fotos', true, 2097152, array['image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Subir foto propia de jugador" on storage.objects;
create policy "Subir foto propia de jugador" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'jugadores-fotos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
    and exists (
      select 1 from public.jugadores
      where lower(jugadores.email) = lower((select auth.jwt() ->> 'email'))
    )
  );

-- Storage devuelve los metadatos de la imagen tras subirla y necesita SELECT.
drop policy if exists "Consultar foto propia de jugador" on storage.objects;
create policy "Consultar foto propia de jugador" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'jugadores-fotos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Quitar foto propia anterior" on storage.objects;
create policy "Quitar foto propia anterior" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'jugadores-fotos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

-- Permitir cambiar solamente foto_path, sin dar UPDATE sobre es_admin u otros datos.
create or replace function public.guardar_foto_perfil(nueva_foto_path text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  usuario_id uuid := (select auth.uid());
  usuario_email text := (select auth.jwt() ->> 'email');
begin
  if usuario_id is null or usuario_email is null then
    raise exception 'Primero tenés que iniciar sesión';
  end if;

  if nueva_foto_path !~
     ('^' || usuario_id::text || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]jpg$') then
    raise exception 'La ruta de la foto no corresponde a tu cuenta';
  end if;

  update public.jugadores
     set foto_path = nueva_foto_path
   where lower(email) = lower(usuario_email);

  if not found then
    raise exception 'Tu cuenta todavía no figura en la lista de jugadores';
  end if;
end;
$$;

revoke all on function public.guardar_foto_perfil(text) from public;
grant execute on function public.guardar_foto_perfil(text) to authenticated;
