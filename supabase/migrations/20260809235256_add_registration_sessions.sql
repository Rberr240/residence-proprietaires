-- =========================================================
-- MIRADOR GOLF - REGISTRATION SESSIONS
-- Migration 003
-- =========================================================
--
-- A valid owner access code creates a short-lived
-- registration session.
--
-- The raw session token is NEVER stored in PostgreSQL.
-- Only its HMAC hash is stored.
-- =========================================================


-- ---------------------------------------------------------
-- 1. REGISTRATION SESSIONS
-- ---------------------------------------------------------

create table public.registration_sessions (
    id uuid primary key default gen_random_uuid(),

    apartment_id uuid not null
        references public.apartments(id)
        on delete cascade,

    access_code_id uuid not null
        references public.access_codes(id)
        on delete cascade,

    token_hash text not null unique,

    expires_at timestamptz not null,

    consumed_at timestamptz,

    created_at timestamptz not null default now(),

    constraint registration_sessions_expiry_check
        check (expires_at > created_at),

    constraint registration_sessions_consumed_check
        check (
            consumed_at is null
            or consumed_at >= created_at
        )
);


-- ---------------------------------------------------------
-- 2. INDEXES
-- ---------------------------------------------------------

create index idx_registration_sessions_token_hash
    on public.registration_sessions(token_hash);

create index idx_registration_sessions_apartment
    on public.registration_sessions(apartment_id);

create index idx_registration_sessions_access_code
    on public.registration_sessions(access_code_id);

create index idx_registration_sessions_expires_at
    on public.registration_sessions(expires_at);


-- ---------------------------------------------------------
-- 3. SECURITY
-- ---------------------------------------------------------

alter table public.registration_sessions
    enable row level security;


-- =========================================================
-- SECURITY MODEL
--
-- No anonymous RLS policy is created.
--
-- GitHub Pages / browser cannot:
--   - read sessions
--   - create sessions directly
--   - consume sessions directly
--
-- Only trusted Edge Functions using the server-side
-- admin client will manipulate this table.
-- =========================================================