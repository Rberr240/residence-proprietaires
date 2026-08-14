-- =========================================================
-- MIRADOR GOLF 1
-- ANNONCES V2
--
-- Architecture sécurisée :
--   - annonces en brouillon / publiées / archivées
--   - catégories et priorités
--   - publication immédiate ou programmée
--   - date d'expiration facultative
--   - ciblage : tous / bloc(s) / lot(s)
--   - accusés de lecture
--   - statistiques Admin
--   - RLS propriétaire / administrateur
-- =========================================================


-- =========================================================
-- 1. ANNONCES
-- =========================================================

create table if not exists public.residence_announcements (

    id uuid primary key
        default gen_random_uuid(),

    title text not null,

    summary text null,

    content text not null,

    category text not null
        default 'general',

    priority text not null
        default 'normal',

    is_pinned boolean not null
        default false,

    status text not null
        default 'draft',

    visible_from timestamptz null,

    expires_at timestamptz null,

    published_at timestamptz null,

    archived_at timestamptz null,

    created_by uuid null
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint residence_announcements_title_not_blank
        check (
            length(trim(title)) > 0
        ),

    constraint residence_announcements_content_not_blank
        check (
            length(trim(content)) > 0
        ),

    constraint residence_announcements_category_check
        check (
            category in (
                'general',
                'information',
                'urgent',
                'works',
                'meeting',
                'security',
                'maintenance',
                'other'
            )
        ),

    constraint residence_announcements_priority_check
        check (
            priority in (
                'normal',
                'high',
                'urgent'
            )
        ),

    constraint residence_announcements_status_check
        check (
            status in (
                'draft',
                'published',
                'archived'
            )
        ),

    constraint residence_announcements_dates_check
        check (
            visible_from is null
            or expires_at is null
            or expires_at > visible_from
        )
);


create index if not exists
    residence_announcements_status_idx
on public.residence_announcements(status);


create index if not exists
    residence_announcements_visible_from_idx
on public.residence_announcements(visible_from);


create index if not exists
    residence_announcements_expires_at_idx
on public.residence_announcements(expires_at);


create index if not exists
    residence_announcements_priority_idx
on public.residence_announcements(priority);


create index if not exists
    residence_announcements_created_by_idx
on public.residence_announcements(created_by);



-- =========================================================
-- 2. CIBLES / AUDIENCE
--
-- target_type = all
--   building_code = NULL
--   owner_account_unit_id = NULL
--
-- target_type = building
--   building_code = 'A'
--   owner_account_unit_id = NULL
--
-- target_type = unit
--   building_code = NULL
--   owner_account_unit_id = UUID du lot
-- =========================================================

create table if not exists public.residence_announcement_targets (

    id uuid primary key
        default gen_random_uuid(),

    announcement_id uuid not null
        references public.residence_announcements(id)
        on delete cascade,

    target_type text not null,

    building_code text null,

    owner_account_unit_id uuid null
        references public.owner_account_units(id)
        on delete cascade,

    created_at timestamptz not null
        default now(),

    constraint residence_announcement_targets_type_check
        check (
            target_type in (
                'all',
                'building',
                'unit'
            )
        ),

    constraint residence_announcement_targets_shape_check
        check (

            (
                target_type = 'all'
                and building_code is null
                and owner_account_unit_id is null
            )

            or

            (
                target_type = 'building'
                and building_code is not null
                and length(trim(building_code)) > 0
                and owner_account_unit_id is null
            )

            or

            (
                target_type = 'unit'
                and building_code is null
                and owner_account_unit_id is not null
            )

        )
);


create index if not exists
    residence_announcement_targets_announcement_idx
on public.residence_announcement_targets(announcement_id);


create index if not exists
    residence_announcement_targets_building_idx
on public.residence_announcement_targets(building_code);


create index if not exists
    residence_announcement_targets_unit_idx
on public.residence_announcement_targets(owner_account_unit_id);


create unique index if not exists
    residence_announcement_targets_all_unique
on public.residence_announcement_targets(announcement_id)
where target_type = 'all';


create unique index if not exists
    residence_announcement_targets_building_unique
on public.residence_announcement_targets(
    announcement_id,
    building_code
)
where target_type = 'building';


create unique index if not exists
    residence_announcement_targets_unit_unique
on public.residence_announcement_targets(
    announcement_id,
    owner_account_unit_id
)
where target_type = 'unit';



-- =========================================================
-- 3. ACCUSÉS DE LECTURE
-- =========================================================

create table if not exists public.owner_announcement_reads (

    id uuid primary key
        default gen_random_uuid(),

    announcement_id uuid not null
        references public.residence_announcements(id)
        on delete cascade,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    first_read_at timestamptz not null
        default now(),

    last_read_at timestamptz not null
        default now(),

    read_count integer not null
        default 1,

    constraint owner_announcement_reads_count_check
        check (
            read_count >= 1
        ),

    constraint owner_announcement_reads_unique
        unique (
            announcement_id,
            owner_account_id
        )
);


create index if not exists
    owner_announcement_reads_announcement_idx
on public.owner_announcement_reads(announcement_id);


create index if not exists
    owner_announcement_reads_owner_idx
on public.owner_announcement_reads(owner_account_id);



-- =========================================================
-- 4. UPDATED_AT
-- =========================================================

create or replace function public.set_residence_announcement_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin

    new.updated_at =
        now();

    return new;

end;
$$;


drop trigger if exists
    residence_announcements_set_updated_at
on public.residence_announcements;


create trigger
    residence_announcements_set_updated_at

before update
on public.residence_announcements

for each row

execute function
    public.set_residence_announcement_updated_at();



-- =========================================================
-- 5. HELPER : LE PROPRIÉTAIRE CONNECTÉ EST-IL CIBLÉ ?
--
-- SECURITY DEFINER évite les problèmes de récursion RLS.
-- La fonction ne lit pas residence_announcements.
-- =========================================================

create or replace function public.owner_matches_announcement_target(
    p_announcement_id uuid
)
returns boolean

language sql

stable

security definer

set search_path = ''

as $$

    select exists (

        select 1

        from public.owner_accounts oa

        where
            oa.auth_user_id =
                auth.uid()

            and
            oa.status =
                'active'

            and exists (

                select 1

                from public.residence_announcement_targets t

                where
                    t.announcement_id =
                        p_announcement_id

                    and (

                        t.target_type =
                            'all'

                        or

                        (
                            t.target_type =
                                'building'

                            and exists (

                                select 1

                                from public.owner_account_units u

                                where
                                    u.owner_account_id =
                                        oa.id

                                    and
                                    u.building_code =
                                        t.building_code

                            )

                        )

                        or

                        (
                            t.target_type =
                                'unit'

                            and exists (

                                select 1

                                from public.owner_account_units u

                                where
                                    u.owner_account_id =
                                        oa.id

                                    and
                                    u.id =
                                        t.owner_account_unit_id

                            )

                        )

                    )

            )

    );

$$;



-- =========================================================
-- 6. RLS
-- =========================================================

alter table public.residence_announcements
    enable row level security;


alter table public.residence_announcement_targets
    enable row level security;


alter table public.owner_announcement_reads
    enable row level security;



-- =========================================================
-- 7. ANNONCES — ADMIN
-- =========================================================

drop policy if exists
    "residence_announcements_admin_select"
on public.residence_announcements;


create policy
    "residence_announcements_admin_select"

on public.residence_announcements

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_announcements_admin_insert"
on public.residence_announcements;


create policy
    "residence_announcements_admin_insert"

on public.residence_announcements

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    status =
        'draft'

    and

    (
        created_by is null
        or
        created_by =
            (select auth.uid())
    )

);


drop policy if exists
    "residence_announcements_admin_update"
on public.residence_announcements;


create policy
    "residence_announcements_admin_update"

on public.residence_announcements

for update

to authenticated

using (

    (select public.is_admin())

    and

    status =
        'draft'

)

with check (

    (select public.is_admin())

    and

    status =
        'draft'

);


drop policy if exists
    "residence_announcements_admin_delete"
on public.residence_announcements;


create policy
    "residence_announcements_admin_delete"

on public.residence_announcements

for delete

to authenticated

using (

    (select public.is_admin())

    and

    status =
        'draft'

);



-- =========================================================
-- 8. ANNONCES — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "residence_announcements_owner_select"
on public.residence_announcements;


create policy
    "residence_announcements_owner_select"

on public.residence_announcements

for select

to authenticated

using (

    status =
        'published'

    and

    (
        visible_from is null
        or
        visible_from <= now()
    )

    and

    (
        expires_at is null
        or
        expires_at > now()
    )

    and

    public.owner_matches_announcement_target(
        residence_announcements.id
    )

);



-- =========================================================
-- 9. CIBLES — ADMIN
-- =========================================================

drop policy if exists
    "residence_announcement_targets_admin_select"
on public.residence_announcement_targets;


create policy
    "residence_announcement_targets_admin_select"

on public.residence_announcement_targets

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_announcement_targets_admin_insert"
on public.residence_announcement_targets;


create policy
    "residence_announcement_targets_admin_insert"

on public.residence_announcement_targets

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_announcements a

        where
            a.id =
                residence_announcement_targets.announcement_id

            and
            a.status =
                'draft'

    )

);


drop policy if exists
    "residence_announcement_targets_admin_update"
on public.residence_announcement_targets;


create policy
    "residence_announcement_targets_admin_update"

on public.residence_announcement_targets

for update

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_announcements a

        where
            a.id =
                residence_announcement_targets.announcement_id

            and
            a.status =
                'draft'

    )

)

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_announcements a

        where
            a.id =
                residence_announcement_targets.announcement_id

            and
            a.status =
                'draft'

    )

);


drop policy if exists
    "residence_announcement_targets_admin_delete"
on public.residence_announcement_targets;


create policy
    "residence_announcement_targets_admin_delete"

on public.residence_announcement_targets

for delete

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_announcements a

        where
            a.id =
                residence_announcement_targets.announcement_id

            and
            a.status =
                'draft'

    )

);



-- =========================================================
-- 10. CIBLES — PROPRIÉTAIRE
--
-- Aucun SELECT direct n'est accordé aux propriétaires sur
-- cette table. Le ciblage est évalué côté serveur par
-- owner_matches_announcement_target().
-- =========================================================


-- =========================================================
-- 11. LECTURES — ADMIN
-- =========================================================

drop policy if exists
    "owner_announcement_reads_admin_select"
on public.owner_announcement_reads;


create policy
    "owner_announcement_reads_admin_select"

on public.owner_announcement_reads

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 12. LECTURES — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "owner_announcement_reads_owner_select"
on public.owner_announcement_reads;


create policy
    "owner_announcement_reads_owner_select"

on public.owner_announcement_reads

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_announcement_reads.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 13. RPC ADMIN : PUBLIER
-- =========================================================

create or replace function public.admin_publish_residence_announcement(
    p_announcement_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_announcement public.residence_announcements%rowtype;

    v_target_count integer;

    v_all_count integer;

    v_effective_visible_from timestamptz;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_announcement

    from public.residence_announcements

    where id =
        p_announcement_id

    for update;


    if not found then

        raise exception
            'Annonce introuvable.';

    end if;


    if
        v_announcement.status <>
        'draft'
    then

        raise exception
            'Seul un brouillon peut être publié.';

    end if;


    select
        count(*),
        count(*) filter (
            where target_type = 'all'
        )

    into
        v_target_count,
        v_all_count

    from public.residence_announcement_targets

    where announcement_id =
        p_announcement_id;


    if
        v_target_count = 0
    then

        raise exception
            'Sélectionnez au moins une audience avant publication.';

    end if;


    if
        v_all_count > 0
        and
        v_target_count > 1
    then

        raise exception
            'L''audience "Tous les propriétaires" ne peut pas être combinée avec d''autres cibles.';

    end if;


    v_effective_visible_from :=
        coalesce(
            v_announcement.visible_from,
            now()
        );


    if
        v_announcement.expires_at is not null
        and
        v_announcement.expires_at <=
        v_effective_visible_from
    then

        raise exception
            'La date d''expiration doit être postérieure à la publication.';

    end if;


    update public.residence_announcements

    set
        status =
            'published',

        visible_from =
            v_effective_visible_from,

        published_at =
            now(),

        archived_at =
            null

    where id =
        p_announcement_id;


    return jsonb_build_object(

        'success',
        true,

        'announcementId',
        p_announcement_id,

        'status',
        'published',

        'visibleFrom',
        v_effective_visible_from,

        'expiresAt',
        v_announcement.expires_at,

        'targetCount',
        v_target_count

    );

end;
$$;



-- =========================================================
-- 14. RPC ADMIN : ARCHIVER
-- =========================================================

create or replace function public.admin_archive_residence_announcement(
    p_announcement_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_announcement public.residence_announcements%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_announcement

    from public.residence_announcements

    where id =
        p_announcement_id

    for update;


    if not found then

        raise exception
            'Annonce introuvable.';

    end if;


    if
        v_announcement.status <>
        'published'
    then

        raise exception
            'Seule une annonce publiée peut être archivée.';

    end if;


    update public.residence_announcements

    set
        status =
            'archived',

        archived_at =
            now()

    where id =
        p_announcement_id;


    return jsonb_build_object(

        'success',
        true,

        'announcementId',
        p_announcement_id,

        'status',
        'archived',

        'archivedAt',
        now()

    );

end;
$$;



-- =========================================================
-- 15. RPC PROPRIÉTAIRE : MARQUER COMME LUE
-- =========================================================

create or replace function public.owner_mark_announcement_read(
    p_announcement_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_announcement public.residence_announcements%rowtype;

    v_read public.owner_announcement_reads%rowtype;

begin

    select oa.id
    into v_owner_account_id

    from public.owner_accounts oa

    where
        oa.auth_user_id =
            (select auth.uid())

        and
        oa.status =
            'active'

    limit 1;


    if
        v_owner_account_id is null
    then

        raise exception
            'Compte propriétaire actif requis.';

    end if;


    select *
    into v_announcement

    from public.residence_announcements

    where id =
        p_announcement_id;


    if not found then

        raise exception
            'Annonce introuvable.';

    end if;


    if
        v_announcement.status <>
        'published'

        or
        (
            v_announcement.visible_from is not null
            and
            v_announcement.visible_from > now()
        )

        or
        (
            v_announcement.expires_at is not null
            and
            v_announcement.expires_at <= now()
        )

        or
        not public.owner_matches_announcement_target(
            p_announcement_id
        )
    then

        raise exception
            'Cette annonce n''est pas accessible à votre compte.';

    end if;


    insert into public.owner_announcement_reads (

        announcement_id,

        owner_account_id,

        first_read_at,

        last_read_at,

        read_count

    )
    values (

        p_announcement_id,

        v_owner_account_id,

        now(),

        now(),

        1

    )

    on conflict (
        announcement_id,
        owner_account_id
    )

    do update set

        last_read_at =
            now(),

        read_count =
            owner_announcement_reads.read_count +
            1

    returning *
    into v_read;


    return jsonb_build_object(

        'success',
        true,

        'announcementId',
        p_announcement_id,

        'ownerAccountId',
        v_owner_account_id,

        'firstReadAt',
        v_read.first_read_at,

        'lastReadAt',
        v_read.last_read_at,

        'readCount',
        v_read.read_count

    );

end;
$$;



-- =========================================================
-- 16. RPC ADMIN : STATISTIQUES DE LECTURE
-- =========================================================

create or replace function public.admin_get_announcement_stats(
    p_announcement_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_announcement public.residence_announcements%rowtype;

    v_eligible integer;

    v_read integer;

    v_unread integer;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_announcement

    from public.residence_announcements

    where id =
        p_announcement_id;


    if not found then

        raise exception
            'Annonce introuvable.';

    end if;


    select
        count(
            distinct oa.id
        )

    into v_eligible

    from public.owner_accounts oa

    where
        oa.status =
            'active'

        and exists (

            select 1

            from public.residence_announcement_targets t

            where
                t.announcement_id =
                    p_announcement_id

                and (

                    t.target_type =
                        'all'

                    or

                    (
                        t.target_type =
                            'building'

                        and exists (

                            select 1

                            from public.owner_account_units u

                            where
                                u.owner_account_id =
                                    oa.id

                                and
                                u.building_code =
                                    t.building_code

                        )

                    )

                    or

                    (
                        t.target_type =
                            'unit'

                        and exists (

                            select 1

                            from public.owner_account_units u

                            where
                                u.owner_account_id =
                                    oa.id

                                and
                                u.id =
                                    t.owner_account_unit_id

                        )

                    )

                )

        );


    select
        count(
            distinct r.owner_account_id
        )

    into v_read

    from public.owner_announcement_reads r

    join public.owner_accounts oa
        on oa.id =
            r.owner_account_id

    where
        r.announcement_id =
            p_announcement_id

        and
        oa.status =
            'active'

        and exists (

            select 1

            from public.residence_announcement_targets t

            where
                t.announcement_id =
                    p_announcement_id

                and (

                    t.target_type =
                        'all'

                    or

                    (
                        t.target_type =
                            'building'

                        and exists (

                            select 1

                            from public.owner_account_units u

                            where
                                u.owner_account_id =
                                    oa.id

                                and
                                u.building_code =
                                    t.building_code

                        )

                    )

                    or

                    (
                        t.target_type =
                            'unit'

                        and exists (

                            select 1

                            from public.owner_account_units u

                            where
                                u.owner_account_id =
                                    oa.id

                                and
                                u.id =
                                    t.owner_account_unit_id

                        )

                    )

                )

        );


    v_unread :=
        greatest(
            v_eligible -
            v_read,
            0
        );


    return jsonb_build_object(

        'announcementId',
        p_announcement_id,

        'status',
        v_announcement.status,

        'eligibleOwners',
        v_eligible,

        'readOwners',
        v_read,

        'unreadOwners',
        v_unread

    );

end;
$$;



-- =========================================================
-- 17. PRIVILÈGES TABLES
-- =========================================================

revoke all
on public.residence_announcements
from anon;


revoke all
on public.residence_announcement_targets
from anon;


revoke all
on public.owner_announcement_reads
from anon;



grant
    select,
    insert,
    delete
on public.residence_announcements
to authenticated;


grant update (
    title,
    summary,
    content,
    category,
    priority,
    is_pinned,
    visible_from,
    expires_at
)
on public.residence_announcements
to authenticated;



grant
    select,
    insert,
    update,
    delete
on public.residence_announcement_targets
to authenticated;



-- Les écritures de lecture passent uniquement par la RPC.
grant select
on public.owner_announcement_reads
to authenticated;



grant all
on public.residence_announcements
to service_role;


grant all
on public.residence_announcement_targets
to service_role;


grant all
on public.owner_announcement_reads
to service_role;



-- =========================================================
-- 18. PRIVILÈGES FUNCTIONS
-- =========================================================

revoke all
on function public.owner_matches_announcement_target(uuid)
from public;


revoke all
on function public.owner_matches_announcement_target(uuid)
from anon;


grant execute
on function public.owner_matches_announcement_target(uuid)
to authenticated;


grant execute
on function public.owner_matches_announcement_target(uuid)
to service_role;



revoke all
on function public.admin_publish_residence_announcement(uuid)
from public;


revoke all
on function public.admin_publish_residence_announcement(uuid)
from anon;


grant execute
on function public.admin_publish_residence_announcement(uuid)
to authenticated;


grant execute
on function public.admin_publish_residence_announcement(uuid)
to service_role;



revoke all
on function public.admin_archive_residence_announcement(uuid)
from public;


revoke all
on function public.admin_archive_residence_announcement(uuid)
from anon;


grant execute
on function public.admin_archive_residence_announcement(uuid)
to authenticated;


grant execute
on function public.admin_archive_residence_announcement(uuid)
to service_role;



revoke all
on function public.owner_mark_announcement_read(uuid)
from public;


revoke all
on function public.owner_mark_announcement_read(uuid)
from anon;


grant execute
on function public.owner_mark_announcement_read(uuid)
to authenticated;


grant execute
on function public.owner_mark_announcement_read(uuid)
to service_role;



revoke all
on function public.admin_get_announcement_stats(uuid)
from public;


revoke all
on function public.admin_get_announcement_stats(uuid)
from anon;


grant execute
on function public.admin_get_announcement_stats(uuid)
to authenticated;


grant execute
on function public.admin_get_announcement_stats(uuid)
to service_role;
