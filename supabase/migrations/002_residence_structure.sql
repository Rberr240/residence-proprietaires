-- =========================================================
-- MIRADOR GOLF - RESIDENCE STRUCTURE
-- Migration 002
-- =========================================================
--
-- Structure connue :
--
-- Bloc A
-- Bloc B
-- Bloc C
-- Bloc D
-- Bloc E
-- Bloc F
-- Bloc H
-- Bloc I
-- Bloc J
-- Bloc K
-- Hôtel
--
-- Le nombre exact d'appartements des blocs sera ajouté plus tard.
-- Hôtel : 35 appartements.
-- =========================================================


-- ---------------------------------------------------------
-- 1. BUILDINGS
-- ---------------------------------------------------------

create table public.buildings (
    id uuid primary key default gen_random_uuid(),

    code text not null unique,

    name text not null,

    type text not null
        check (
            type in (
                'block',
                'hotel'
            )
        ),

    apartment_count integer
        check (
            apartment_count is null
            or apartment_count >= 0
        ),

    active boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 2. SECURITY
-- ---------------------------------------------------------

alter table public.buildings
    enable row level security;


-- ---------------------------------------------------------
-- 3. AUTOMATIC updated_at
-- ---------------------------------------------------------

create trigger buildings_set_updated_at
before update on public.buildings
for each row
execute function public.set_updated_at();


-- ---------------------------------------------------------
-- 4. MIRADOR GOLF BUILDINGS
-- ---------------------------------------------------------

insert into public.buildings (
    code,
    name,
    type,
    apartment_count
)
values
    ('A',     'Bloc A', 'block', null),
    ('B',     'Bloc B', 'block', null),
    ('C',     'Bloc C', 'block', null),
    ('D',     'Bloc D', 'block', null),
    ('E',     'Bloc E', 'block', null),
    ('F',     'Bloc F', 'block', null),
    ('H',     'Bloc H', 'block', null),
    ('I',     'Bloc I', 'block', null),
    ('J',     'Bloc J', 'block', null),
    ('K',     'Bloc K', 'block', null),
    ('HOTEL', 'Hôtel',  'hotel', 35)
on conflict (code) do nothing;


-- ---------------------------------------------------------
-- 5. CONNECT APARTMENTS TO BUILDINGS
-- ---------------------------------------------------------

alter table public.apartments
add column building_id uuid;


alter table public.apartments
add constraint apartments_building_id_fkey
foreign key (building_id)
references public.buildings(id)
on delete restrict;


-- ---------------------------------------------------------
-- 6. REMOVE OLD BUILDING TEXT COLUMN
-- ---------------------------------------------------------

alter table public.apartments
drop column if exists building;


-- ---------------------------------------------------------
-- 7. FIX APARTMENT UNIQUENESS
-- ---------------------------------------------------------
--
-- Apartment "01" can exist in several different blocks.
--
-- Valid:
-- Bloc A + 01
-- Bloc B + 01
--
-- Invalid:
-- Bloc A + 01 twice
-- ---------------------------------------------------------

alter table public.apartments
drop constraint if exists apartments_apartment_number_key;


alter table public.apartments
add constraint apartments_building_apartment_unique
unique (
    building_id,
    apartment_number
);


-- ---------------------------------------------------------
-- 8. BUILDING IS REQUIRED FOR EVERY APARTMENT
-- ---------------------------------------------------------

alter table public.apartments
alter column building_id set not null;


-- ---------------------------------------------------------
-- 9. INDEX
-- ---------------------------------------------------------

create index idx_apartments_building
on public.apartments(building_id);


-- =========================================================
-- RESULT
--
-- buildings
--   |
--   +-- Bloc A
--   +-- Bloc B
--   +-- Bloc C
--   +-- Bloc D
--   +-- Bloc E
--   +-- Bloc F
--   +-- Bloc H
--   +-- Bloc I
--   +-- Bloc J
--   +-- Bloc K
--   +-- Hôtel (35 apartments)
--
-- buildings
--     |
--     +---- apartments
--              |
--              +---- owners
--              +---- access_codes
--
-- No anonymous RLS policy is created.
-- =========================================================