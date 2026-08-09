-- =========================================================
-- MIRADOR GOLF - INITIAL DATABASE SCHEMA
-- Version 1
-- =========================================================


-- ---------------------------------------------------------
-- 1. APARTMENTS
-- ---------------------------------------------------------

create table public.apartments (
    id uuid primary key default gen_random_uuid(),

    building text,
    floor integer,

    apartment_number text not null unique,

    created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 2. ACCESS CODES
-- ---------------------------------------------------------

create table public.access_codes (
    id uuid primary key default gen_random_uuid(),

    apartment_id uuid not null
        references public.apartments(id)
        on delete cascade,

    code_hash text not null unique,

    active boolean not null default true,

    used_at timestamptz,
    expires_at timestamptz,

    created_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 3. OWNERS
-- ---------------------------------------------------------

create table public.owners (
    id uuid primary key default gen_random_uuid(),

    apartment_id uuid not null
        references public.apartments(id)
        on delete restrict,

    first_name text not null,
    last_name text not null,

    phone text not null,
    whatsapp text,
    email text,

    verified boolean not null default false,

    consent boolean not null default false,
    consent_at timestamptz,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 4. MEETINGS
-- ---------------------------------------------------------

create table public.meetings (
    id uuid primary key default gen_random_uuid(),

    title text not null,

    meeting_date timestamptz,

    location text,
    description text,

    status text not null default 'draft'
        check (
            status in (
                'draft',
                'scheduled',
                'completed',
                'cancelled'
            )
        ),

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);


-- ---------------------------------------------------------
-- 5. MEETING RESPONSES
-- ---------------------------------------------------------

create table public.meeting_responses (
    id uuid primary key default gen_random_uuid(),

    meeting_id uuid not null
        references public.meetings(id)
        on delete cascade,

    owner_id uuid not null
        references public.owners(id)
        on delete cascade,

    attendance text
        check (
            attendance is null
            or attendance in (
                'yes',
                'no',
                'maybe'
            )
        ),

    availability text[] not null default '{}',

    subject text,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    unique (meeting_id, owner_id)
);


-- ---------------------------------------------------------
-- 6. INDEXES
-- ---------------------------------------------------------

create index idx_access_codes_apartment
    on public.access_codes(apartment_id);

create index idx_access_codes_active
    on public.access_codes(active);

create index idx_owners_apartment
    on public.owners(apartment_id);

create index idx_meeting_responses_meeting
    on public.meeting_responses(meeting_id);

create index idx_meeting_responses_owner
    on public.meeting_responses(owner_id);


-- ---------------------------------------------------------
-- 7. AUTOMATIC updated_at
-- ---------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;


create trigger owners_set_updated_at
before update on public.owners
for each row
execute function public.set_updated_at();


create trigger meetings_set_updated_at
before update on public.meetings
for each row
execute function public.set_updated_at();


create trigger meeting_responses_set_updated_at
before update on public.meeting_responses
for each row
execute function public.set_updated_at();


-- ---------------------------------------------------------
-- 8. ENABLE ROW LEVEL SECURITY
-- ---------------------------------------------------------

alter table public.apartments
    enable row level security;

alter table public.access_codes
    enable row level security;

alter table public.owners
    enable row level security;

alter table public.meetings
    enable row level security;

alter table public.meeting_responses
    enable row level security;


-- =========================================================
-- IMPORTANT
--
-- No public RLS policies are created yet.
--
-- Therefore the frontend cannot currently read:
-- - owners
-- - phone numbers
-- - access codes
-- - apartments
-- - meeting responses
--
-- We will create controlled access later.
-- =========================================================