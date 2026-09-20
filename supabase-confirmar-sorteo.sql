alter table public.partidos
add column if not exists sorteo_confirmado boolean not null default false;

drop policy if exists "Admin confirma el sorteo" on public.partidos;

create policy "Admin confirma el sorteo"
on public.partidos
for update
to authenticated
using (
  exists (
    select 1
    from public.jugadores
    where jugadores.email = (auth.jwt() ->> 'email')
      and jugadores.es_admin = true
  )
)
with check (
  exists (
    select 1
    from public.jugadores
    where jugadores.email = (auth.jwt() ->> 'email')
      and jugadores.es_admin = true
  )
);

drop policy if exists "Admin crea partidos" on public.partidos;

create policy "Admin crea partidos"
on public.partidos
for insert
to authenticated
with check (
  exists (
    select 1
    from public.jugadores
    where jugadores.email = (auth.jwt() ->> 'email')
      and jugadores.es_admin = true
  )
);
