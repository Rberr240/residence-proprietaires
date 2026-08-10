create table public.owner_submissions (
    id uuid primary key default gen_random_uuid(),

    building_code text not null
        check (
            building_code in (
                'A','B','C','D','E','F',
                'H','I','J','K','HOTEL'
            )
        ),

    apartment_number text not null
        check (length(trim(apartment_number)) between 1 and 30),

    first_name text not null
        check (length(trim(first_name)) between 1 and 100),

    last_name text not null
        check (length(trim(last_name)) between 1 and 100),

    phone text not null
        check (length(trim(phone)) between 5 and 30),

    whatsapp text,

    email text,

    attendance text
        check (
            attendance is null
            or attendance in ('yes','no','maybe')
        ),

    availability text[] not null default '{}'
        check (
            availability <@
            array['morning','afternoon','evening']::text[]
        ),

    subject text
        check (
            subject is null
            or length(subject) <= 1000
        ),

    consent boolean not null
        check (consent = true),

    status text not null default 'pending'
        check (
            status in ('pending','verified','rejected')
        ),

    created_at timestamptz not null default now()
);

alter table public.owner_submissions
enable row level security;

revoke all
on public.owner_submissions
from anon, authenticated;

grant insert (
    building_code,
    apartment_number,
    first_name,
    last_name,
    phone,
    whatsapp,
    email,
    attendance,
    availability,
    subject,
    consent
)
on public.owner_submissions
to anon;

grant all
on public.owner_submissions
to service_role;

create policy owner_submissions_public_insert
on public.owner_submissions
for insert
to anon
with check (
    consent = true
    and status = 'pending'
);