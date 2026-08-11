-- =========================================================
-- MIRADOR GOLF 1
-- Administration access control
-- =========================================================


-- =========================================================
-- 1. ADMIN USERS
-- =========================================================

create table public.admin_users (

    id uuid primary key default gen_random_uuid(),

    auth_user_id uuid not null unique
        references auth.users(id)
        on delete cascade,

    display_name text,

    role text not null default 'admin'
        check (
            role in (
                'admin',
                'super_admin'
            )
        ),

    is_active boolean not null default true,

    created_at timestamptz not null default now()
);


-- =========================================================
-- 2. RLS
-- =========================================================

alter table public.admin_users
enable row level security;


revoke all
on public.admin_users
from anon, authenticated;


-- =========================================================
-- 3. HELPER FUNCTION
--
-- Permet aux politiques RLS de vérifier qu'un utilisateur
-- authentifié fait bien partie des administrateurs actifs.
-- =========================================================

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$

    select exists (

        select 1

        from public.admin_users

        where auth_user_id = auth.uid()

        and is_active = true

    );

$$;


revoke all
on function public.is_admin()
from public;


grant execute
on function public.is_admin()
to authenticated;


-- =========================================================
-- 4. ADMIN PEUT LIRE SA PROPRE FICHE
-- =========================================================

grant select
on public.admin_users
to authenticated;


create policy admin_users_select_self
on public.admin_users
for select
to authenticated
using (
    auth_user_id = (select auth.uid())
);


-- =========================================================
-- 5. OWNER SUBMISSIONS
--
-- Les propriétaires anonymes peuvent toujours INSERT
-- grâce à la politique existante.
--
-- Seuls les administrateurs authentifiés peuvent lire
-- ou modifier les inscriptions.
-- =========================================================

grant select, update
on public.owner_submissions
to authenticated;


create policy owner_submissions_admin_select
on public.owner_submissions
for select
to authenticated
using (
    public.is_admin()
);


create policy owner_submissions_admin_update
on public.owner_submissions
for update
to authenticated
using (
    public.is_admin()
)
with check (
    public.is_admin()
);


-- =========================================================
-- 6. OWNER ACCOUNTS
--
-- Les propriétaires gardent leur politique SELECT personnelle.
-- Les admins peuvent également consulter les comptes.
-- =========================================================

create policy owner_accounts_admin_select
on public.owner_accounts
for select
to authenticated
using (
    public.is_admin()
);


create policy owner_account_units_admin_select
on public.owner_account_units
for select
to authenticated
using (
    public.is_admin()
);


-- =========================================================
-- 7. SERVICE ROLE
-- =========================================================

grant all
on public.admin_users
to service_role;