-- =========================================================
-- MIRADOR GOLF 1
-- Owner accounts + properties + activation codes
-- =========================================================


-- =========================================================
-- 1. OWNER ACCOUNTS
--
-- Un compte = une personne.
-- Une personne pourra posséder plusieurs appartements.
-- =========================================================

create table public.owner_accounts (

    id uuid primary key default gen_random_uuid(),

    -- Sera rempli après activation du compte Supabase Auth.
    auth_user_id uuid unique
        references auth.users(id)
        on delete set null,

    first_name text not null
        check (length(trim(first_name)) between 1 and 100),

    last_name text not null
        check (length(trim(last_name)) between 1 and 100),

    -- Numéro tel tel que nous voulons l'afficher.
    phone text not null
        check (length(trim(phone)) between 5 and 30),

    -- Numéro normalisé futur, par exemple +2126XXXXXXXX.
    -- Il servira pour la connexion Supabase Auth.
    phone_e164 text unique,

    whatsapp text,

    email text,

    status text not null default 'invited'
        check (
            status in (
                'invited',
                'active',
                'suspended',
                'disabled'
            )
        ),

    activated_at timestamptz,

    created_at timestamptz not null default now()
);


-- =========================================================
-- 2. APPARTEMENTS LIÉS À UN COMPTE
--
-- Un propriétaire peut avoir plusieurs appartements.
-- Un appartement pourra aussi être rattaché plus tard
-- à plusieurs copropriétaires si nécessaire.
-- =========================================================

create table public.owner_account_units (

    id uuid primary key default gen_random_uuid(),

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    -- Formulaire collecte.html ayant servi à créer cette entrée.
    submission_id uuid not null unique
        references public.owner_submissions(id)
        on delete restrict,

    building_code text not null
        check (length(trim(building_code)) between 1 and 20),

    apartment_number text not null
        check (length(trim(apartment_number)) between 1 and 30),

    is_primary boolean not null default false,

    created_at timestamptz not null default now(),

    unique (
        owner_account_id,
        building_code,
        apartment_number
    )
);


-- =========================================================
-- 3. CODES D'ACTIVATION
--
-- IMPORTANT :
-- Le code propriétaire ne sera JAMAIS enregistré en clair.
-- On stockera uniquement son HMAC/SHA-256.
-- =========================================================

create table public.owner_activation_codes (

    id uuid primary key default gen_random_uuid(),

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    code_hash text not null unique
        check (length(code_hash) = 64),

    expires_at timestamptz not null,

    used_at timestamptz,

    revoked_at timestamptz,

    created_at timestamptz not null default now(),

    check (
        expires_at > created_at
    )
);


-- =========================================================
-- 4. INDEX
-- =========================================================

create index owner_account_units_owner_idx
on public.owner_account_units(owner_account_id);


create index owner_activation_codes_owner_idx
on public.owner_activation_codes(owner_account_id);


create index owner_activation_codes_expiry_idx
on public.owner_activation_codes(expires_at);


-- Un seul code non consommé/non révoqué à la fois par compte.
create unique index owner_activation_codes_one_open_code_idx
on public.owner_activation_codes(owner_account_id)
where used_at is null
and revoked_at is null;


-- =========================================================
-- 5. ROW LEVEL SECURITY
-- =========================================================

alter table public.owner_accounts
enable row level security;

alter table public.owner_account_units
enable row level security;

alter table public.owner_activation_codes
enable row level security;


-- =========================================================
-- 6. RETIRER LES DROITS PUBLICS
-- =========================================================

revoke all
on public.owner_accounts
from anon, authenticated;

revoke all
on public.owner_account_units
from anon, authenticated;

revoke all
on public.owner_activation_codes
from anon, authenticated;


-- =========================================================
-- 7. PROPRIÉTAIRE CONNECTÉ
--
-- Il peut uniquement LIRE son propre compte
-- et ses propres appartements.
-- =========================================================

grant select
on public.owner_accounts
to authenticated;


grant select
on public.owner_account_units
to authenticated;


create policy owner_accounts_select_own
on public.owner_accounts
for select
to authenticated
using (
    auth_user_id is not null
    and
    (select auth.uid()) = auth_user_id
);


create policy owner_account_units_select_own
on public.owner_account_units
for select
to authenticated
using (

    exists (

        select 1

        from public.owner_accounts account

        where account.id = owner_account_units.owner_account_id

        and account.auth_user_id is not null

        and account.auth_user_id = (select auth.uid())

    )

);


-- =========================================================
-- 8. ACTIVATION CODES
--
-- AUCUN accès direct depuis le navigateur.
-- Ils seront manipulés uniquement côté serveur
-- par nos Edge Functions.
-- =========================================================

revoke all
on public.owner_activation_codes
from anon, authenticated;


-- =========================================================
-- 9. SERVICE ROLE
-- =========================================================

grant all
on public.owner_accounts
to service_role;

grant all
on public.owner_account_units
to service_role;

grant all
on public.owner_activation_codes
to service_role;