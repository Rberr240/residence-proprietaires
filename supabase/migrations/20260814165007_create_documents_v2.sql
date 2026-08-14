-- =========================================================
-- MIRADOR GOLF 1
-- DOCUMENTS V2 + SUPABASE STORAGE PRIVÉ
--
-- Architecture :
--   - métadonnées documents
--   - bucket privé residence-documents
--   - ciblage : tous / bloc / lot
--   - brouillon / publié / archivé
--   - publication programmée + expiration facultative
--   - accès propriétaire via RLS
--   - journal vue / téléchargement
--   - statistiques Admin
--
-- Le fichier physique est manipulé via Supabase Storage API.
-- La base stocke uniquement ses métadonnées et son chemin.
-- =========================================================


-- =========================================================
-- 1. BUCKET STORAGE PRIVÉ
-- =========================================================

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'residence-documents',
    'residence-documents',
    false,
    26214400,
    array[
        'application/pdf',
        'image/jpeg',
        'image/png',
        'text/plain',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    ]::text[]
)
on conflict (id)
do update set
    name =
        excluded.name,

    public =
        false,

    file_size_limit =
        excluded.file_size_limit,

    allowed_mime_types =
        excluded.allowed_mime_types;



-- =========================================================
-- 2. DOCUMENTS
-- =========================================================

create table if not exists public.residence_documents (

    id uuid primary key
        default gen_random_uuid(),

    title text not null,

    description text null,

    category text not null
        default 'other',

    status text not null
        default 'draft',

    storage_bucket text not null
        default 'residence-documents',

    storage_path text null,

    original_filename text null,

    mime_type text null,

    file_size_bytes bigint null,

    checksum_sha256 text null,

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

    constraint residence_documents_title_not_blank
        check (
            length(trim(title)) > 0
        ),

    constraint residence_documents_category_check
        check (
            category in (
                'minutes',
                'regulation',
                'budget',
                'invoice',
                'contract',
                'insurance',
                'works',
                'convocation',
                'report',
                'other'
            )
        ),

    constraint residence_documents_status_check
        check (
            status in (
                'draft',
                'published',
                'archived'
            )
        ),

    constraint residence_documents_storage_bucket_check
        check (
            storage_bucket =
                'residence-documents'
        ),

    constraint residence_documents_storage_path_check
        check (
            storage_path is null
            or
            length(trim(storage_path)) > 0
        ),

    constraint residence_documents_filename_check
        check (
            original_filename is null
            or
            length(trim(original_filename)) > 0
        ),

    constraint residence_documents_mime_type_check
        check (
            mime_type is null
            or
            length(trim(mime_type)) > 0
        ),

    constraint residence_documents_file_size_check
        check (
            file_size_bytes is null
            or
            (
                file_size_bytes > 0
                and
                file_size_bytes <= 26214400
            )
        ),

    constraint residence_documents_checksum_check
        check (
            checksum_sha256 is null
            or
            checksum_sha256 ~ '^[0-9a-fA-F]{64}$'
        ),

    constraint residence_documents_dates_check
        check (
            visible_from is null
            or
            expires_at is null
            or
            expires_at > visible_from
        )
);


create index if not exists
    residence_documents_status_idx
on public.residence_documents(status);


create index if not exists
    residence_documents_visible_from_idx
on public.residence_documents(visible_from);


create index if not exists
    residence_documents_expires_at_idx
on public.residence_documents(expires_at);


create index if not exists
    residence_documents_category_idx
on public.residence_documents(category);


create unique index if not exists
    residence_documents_storage_path_unique
on public.residence_documents(storage_bucket, storage_path)
where storage_path is not null;



-- =========================================================
-- 3. CIBLES / AUDIENCE
-- =========================================================

create table if not exists public.residence_document_targets (

    id uuid primary key
        default gen_random_uuid(),

    document_id uuid not null
        references public.residence_documents(id)
        on delete cascade,

    target_type text not null,

    building_code text null,

    owner_account_unit_id uuid null
        references public.owner_account_units(id)
        on delete cascade,

    created_at timestamptz not null
        default now(),

    constraint residence_document_targets_type_check
        check (
            target_type in (
                'all',
                'building',
                'unit'
            )
        ),

    constraint residence_document_targets_shape_check
        check (

            (
                target_type =
                    'all'

                and
                building_code is null

                and
                owner_account_unit_id is null
            )

            or

            (
                target_type =
                    'building'

                and
                building_code is not null

                and
                length(trim(building_code)) > 0

                and
                owner_account_unit_id is null
            )

            or

            (
                target_type =
                    'unit'

                and
                building_code is null

                and
                owner_account_unit_id is not null
            )

        )
);


create index if not exists
    residence_document_targets_document_idx
on public.residence_document_targets(document_id);


create index if not exists
    residence_document_targets_building_idx
on public.residence_document_targets(building_code);


create index if not exists
    residence_document_targets_unit_idx
on public.residence_document_targets(owner_account_unit_id);


create unique index if not exists
    residence_document_targets_all_unique
on public.residence_document_targets(document_id)
where target_type = 'all';


create unique index if not exists
    residence_document_targets_building_unique
on public.residence_document_targets(
    document_id,
    building_code
)
where target_type = 'building';


create unique index if not exists
    residence_document_targets_unit_unique
on public.residence_document_targets(
    document_id,
    owner_account_unit_id
)
where target_type = 'unit';



-- =========================================================
-- 4. JOURNAL D'ACCÈS PROPRIÉTAIRE
-- =========================================================

create table if not exists public.owner_document_accesses (

    id uuid primary key
        default gen_random_uuid(),

    document_id uuid not null
        references public.residence_documents(id)
        on delete cascade,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    first_view_at timestamptz null,

    last_view_at timestamptz null,

    view_count integer not null
        default 0,

    first_download_at timestamptz null,

    last_download_at timestamptz null,

    download_count integer not null
        default 0,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint owner_document_accesses_view_count_check
        check (
            view_count >= 0
        ),

    constraint owner_document_accesses_download_count_check
        check (
            download_count >= 0
        ),

    constraint owner_document_accesses_unique
        unique (
            document_id,
            owner_account_id
        )
);


create index if not exists
    owner_document_accesses_document_idx
on public.owner_document_accesses(document_id);


create index if not exists
    owner_document_accesses_owner_idx
on public.owner_document_accesses(owner_account_id);



-- =========================================================
-- 5. UPDATED_AT
-- =========================================================

create or replace function public.set_residence_document_updated_at()
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
    residence_documents_set_updated_at
on public.residence_documents;


create trigger
    residence_documents_set_updated_at

before update
on public.residence_documents

for each row

execute function
    public.set_residence_document_updated_at();


drop trigger if exists
    owner_document_accesses_set_updated_at
on public.owner_document_accesses;


create trigger
    owner_document_accesses_set_updated_at

before update
on public.owner_document_accesses

for each row

execute function
    public.set_residence_document_updated_at();



-- =========================================================
-- 6. HELPER : LE PROPRIÉTAIRE CONNECTÉ EST-IL CIBLÉ ?
-- =========================================================

create or replace function public.owner_matches_document_target(
    p_document_id uuid
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

                from public.residence_document_targets t

                where
                    t.document_id =
                        p_document_id

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
-- 7. RLS — TABLES PUBLIC
-- =========================================================

alter table public.residence_documents
    enable row level security;


alter table public.residence_document_targets
    enable row level security;


alter table public.owner_document_accesses
    enable row level security;



-- =========================================================
-- 8. DOCUMENTS — ADMIN
-- =========================================================

drop policy if exists
    "residence_documents_admin_select"
on public.residence_documents;


create policy
    "residence_documents_admin_select"

on public.residence_documents

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_documents_admin_insert"
on public.residence_documents;


create policy
    "residence_documents_admin_insert"

on public.residence_documents

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
    "residence_documents_admin_update"
on public.residence_documents;


create policy
    "residence_documents_admin_update"

on public.residence_documents

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
    "residence_documents_admin_delete"
on public.residence_documents;


create policy
    "residence_documents_admin_delete"

on public.residence_documents

for delete

to authenticated

using (

    (select public.is_admin())

    and

    status =
        'draft'

);



-- =========================================================
-- 9. DOCUMENTS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "residence_documents_owner_select"
on public.residence_documents;


create policy
    "residence_documents_owner_select"

on public.residence_documents

for select

to authenticated

using (

    status =
        'published'

    and

    storage_path is not null

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

    public.owner_matches_document_target(
        residence_documents.id
    )

);



-- =========================================================
-- 10. CIBLES — ADMIN UNIQUEMENT
-- =========================================================

drop policy if exists
    "residence_document_targets_admin_select"
on public.residence_document_targets;


create policy
    "residence_document_targets_admin_select"

on public.residence_document_targets

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_document_targets_admin_insert"
on public.residence_document_targets;


create policy
    "residence_document_targets_admin_insert"

on public.residence_document_targets

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_documents d

        where
            d.id =
                residence_document_targets.document_id

            and
            d.status =
                'draft'

    )

);


drop policy if exists
    "residence_document_targets_admin_update"
on public.residence_document_targets;


create policy
    "residence_document_targets_admin_update"

on public.residence_document_targets

for update

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_documents d

        where
            d.id =
                residence_document_targets.document_id

            and
            d.status =
                'draft'

    )

)

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_documents d

        where
            d.id =
                residence_document_targets.document_id

            and
            d.status =
                'draft'

    )

);


drop policy if exists
    "residence_document_targets_admin_delete"
on public.residence_document_targets;


create policy
    "residence_document_targets_admin_delete"

on public.residence_document_targets

for delete

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_documents d

        where
            d.id =
                residence_document_targets.document_id

            and
            d.status =
                'draft'

    )

);



-- =========================================================
-- 11. JOURNAL D'ACCÈS — ADMIN
-- =========================================================

drop policy if exists
    "owner_document_accesses_admin_select"
on public.owner_document_accesses;


create policy
    "owner_document_accesses_admin_select"

on public.owner_document_accesses

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 12. JOURNAL D'ACCÈS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "owner_document_accesses_owner_select"
on public.owner_document_accesses;


create policy
    "owner_document_accesses_owner_select"

on public.owner_document_accesses

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_document_accesses.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 13. STORAGE — ADMIN
-- =========================================================

drop policy if exists
    "residence_documents_storage_admin_select"
on storage.objects;


create policy
    "residence_documents_storage_admin_select"

on storage.objects

for select

to authenticated

using (

    bucket_id =
        'residence-documents'

    and

    (select public.is_admin())

);


drop policy if exists
    "residence_documents_storage_admin_insert"
on storage.objects;


create policy
    "residence_documents_storage_admin_insert"

on storage.objects

for insert

to authenticated

with check (

    bucket_id =
        'residence-documents'

    and

    (select public.is_admin())

);


drop policy if exists
    "residence_documents_storage_admin_update"
on storage.objects;


create policy
    "residence_documents_storage_admin_update"

on storage.objects

for update

to authenticated

using (

    bucket_id =
        'residence-documents'

    and

    (select public.is_admin())

)

with check (

    bucket_id =
        'residence-documents'

    and

    (select public.is_admin())

);


drop policy if exists
    "residence_documents_storage_admin_delete"
on storage.objects;


create policy
    "residence_documents_storage_admin_delete"

on storage.objects

for delete

to authenticated

using (

    bucket_id =
        'residence-documents'

    and

    (select public.is_admin())

);



-- =========================================================
-- 14. STORAGE — PROPRIÉTAIRE
--
-- Un propriétaire ne peut lire qu'un objet correspondant à
-- un document publié, actif et ciblé vers son compte.
-- =========================================================

drop policy if exists
    "residence_documents_storage_owner_select"
on storage.objects;


create policy
    "residence_documents_storage_owner_select"

on storage.objects

for select

to authenticated

using (

    bucket_id =
        'residence-documents'

    and

    exists (

        select 1

        from public.residence_documents d

        where
            d.storage_bucket =
                bucket_id

            and
            d.storage_path =
                name

            and
            d.status =
                'published'

            and
            (
                d.visible_from is null
                or
                d.visible_from <= now()
            )

            and
            (
                d.expires_at is null
                or
                d.expires_at > now()
            )

            and
            public.owner_matches_document_target(
                d.id
            )

    )

);



-- =========================================================
-- 15. RPC ADMIN : PUBLIER UN DOCUMENT
-- =========================================================

create or replace function public.admin_publish_residence_document(
    p_document_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_document public.residence_documents%rowtype;

    v_target_count integer;

    v_all_count integer;

    v_effective_visible_from timestamptz;

    v_storage_exists boolean;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_document

    from public.residence_documents

    where id =
        p_document_id

    for update;


    if not found then

        raise exception
            'Document introuvable.';

    end if;


    if
        v_document.status <>
        'draft'
    then

        raise exception
            'Seul un brouillon peut être publié.';

    end if;


    if
        v_document.storage_path is null

        or
        v_document.original_filename is null

        or
        v_document.mime_type is null

        or
        v_document.file_size_bytes is null
    then

        raise exception
            'Le fichier du document est incomplet ou absent.';

    end if;


    select exists (

        select 1

        from storage.objects o

        where
            o.bucket_id =
                v_document.storage_bucket

            and
            o.name =
                v_document.storage_path

    )
    into v_storage_exists;


    if not v_storage_exists then

        raise exception
            'Le fichier est introuvable dans Supabase Storage.';

    end if;


    select
        count(*),
        count(*) filter (
            where target_type = 'all'
        )

    into
        v_target_count,
        v_all_count

    from public.residence_document_targets

    where document_id =
        p_document_id;


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
            v_document.visible_from,
            now()
        );


    if
        v_document.expires_at is not null

        and

        v_document.expires_at <=
        v_effective_visible_from
    then

        raise exception
            'La date d''expiration doit être postérieure à la publication.';

    end if;


    update public.residence_documents

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
        p_document_id;


    return jsonb_build_object(

        'success',
        true,

        'documentId',
        p_document_id,

        'status',
        'published',

        'visibleFrom',
        v_effective_visible_from,

        'expiresAt',
        v_document.expires_at,

        'targetCount',
        v_target_count,

        'storageBucket',
        v_document.storage_bucket,

        'storagePath',
        v_document.storage_path

    );

end;
$$;



-- =========================================================
-- 16. RPC ADMIN : ARCHIVER
-- =========================================================

create or replace function public.admin_archive_residence_document(
    p_document_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_document public.residence_documents%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_document

    from public.residence_documents

    where id =
        p_document_id

    for update;


    if not found then

        raise exception
            'Document introuvable.';

    end if;


    if
        v_document.status <>
        'published'
    then

        raise exception
            'Seul un document publié peut être archivé.';

    end if;


    update public.residence_documents

    set
        status =
            'archived',

        archived_at =
            now()

    where id =
        p_document_id;


    return jsonb_build_object(

        'success',
        true,

        'documentId',
        p_document_id,

        'status',
        'archived',

        'archivedAt',
        now()

    );

end;
$$;



-- =========================================================
-- 17. RPC PROPRIÉTAIRE : JOURNALISER UN ACCÈS
-- =========================================================

create or replace function public.owner_log_document_access(
    p_document_id uuid,
    p_action text
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_document public.residence_documents%rowtype;

    v_access public.owner_document_accesses%rowtype;

begin

    if
        p_action not in (
            'view',
            'download'
        )
    then

        raise exception
            'Action document invalide.';

    end if;


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
    into v_document

    from public.residence_documents

    where id =
        p_document_id;


    if not found then

        raise exception
            'Document introuvable.';

    end if;


    if
        v_document.status <>
        'published'

        or

        v_document.storage_path is null

        or

        (
            v_document.visible_from is not null
            and
            v_document.visible_from > now()
        )

        or

        (
            v_document.expires_at is not null
            and
            v_document.expires_at <= now()
        )

        or

        not public.owner_matches_document_target(
            p_document_id
        )
    then

        raise exception
            'Ce document n''est pas accessible à votre compte.';

    end if;


    if
        p_action =
        'view'
    then

        insert into public.owner_document_accesses (

            document_id,

            owner_account_id,

            first_view_at,

            last_view_at,

            view_count,

            download_count

        )
        values (

            p_document_id,

            v_owner_account_id,

            now(),

            now(),

            1,

            0

        )

        on conflict (
            document_id,
            owner_account_id
        )

        do update set

            first_view_at =
                coalesce(
                    owner_document_accesses.first_view_at,
                    now()
                ),

            last_view_at =
                now(),

            view_count =
                owner_document_accesses.view_count +
                1

        returning *
        into v_access;

    else

        insert into public.owner_document_accesses (

            document_id,

            owner_account_id,

            view_count,

            first_download_at,

            last_download_at,

            download_count

        )
        values (

            p_document_id,

            v_owner_account_id,

            0,

            now(),

            now(),

            1

        )

        on conflict (
            document_id,
            owner_account_id
        )

        do update set

            first_download_at =
                coalesce(
                    owner_document_accesses.first_download_at,
                    now()
                ),

            last_download_at =
                now(),

            download_count =
                owner_document_accesses.download_count +
                1

        returning *
        into v_access;

    end if;


    return jsonb_build_object(

        'success',
        true,

        'documentId',
        p_document_id,

        'ownerAccountId',
        v_owner_account_id,

        'action',
        p_action,

        'viewCount',
        v_access.view_count,

        'downloadCount',
        v_access.download_count,

        'firstViewAt',
        v_access.first_view_at,

        'lastViewAt',
        v_access.last_view_at,

        'firstDownloadAt',
        v_access.first_download_at,

        'lastDownloadAt',
        v_access.last_download_at

    );

end;
$$;



-- =========================================================
-- 18. RPC ADMIN : STATISTIQUES
-- =========================================================

create or replace function public.admin_get_residence_document_stats(
    p_document_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_document public.residence_documents%rowtype;

    v_eligible integer;

    v_viewed integer;

    v_downloaded integer;

    v_total_views bigint;

    v_total_downloads bigint;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_document

    from public.residence_documents

    where id =
        p_document_id;


    if not found then

        raise exception
            'Document introuvable.';

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

            from public.residence_document_targets t

            where
                t.document_id =
                    p_document_id

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
            distinct a.owner_account_id
        ) filter (
            where a.view_count > 0
        ),

        count(
            distinct a.owner_account_id
        ) filter (
            where a.download_count > 0
        ),

        coalesce(
            sum(a.view_count),
            0
        ),

        coalesce(
            sum(a.download_count),
            0
        )

    into
        v_viewed,
        v_downloaded,
        v_total_views,
        v_total_downloads

    from public.owner_document_accesses a

    join public.owner_accounts oa
        on oa.id =
            a.owner_account_id

    where
        a.document_id =
            p_document_id

        and
        oa.status =
            'active';


    return jsonb_build_object(

        'documentId',
        p_document_id,

        'status',
        v_document.status,

        'eligibleOwners',
        v_eligible,

        'viewedOwners',
        v_viewed,

        'downloadedOwners',
        v_downloaded,

        'totalViews',
        v_total_views,

        'totalDownloads',
        v_total_downloads

    );

end;
$$;



-- =========================================================
-- 19. PRIVILÈGES TABLES PUBLIC
-- =========================================================

revoke all
on public.residence_documents
from anon;


revoke all
on public.residence_document_targets
from anon;


revoke all
on public.owner_document_accesses
from anon;



grant
    select,
    insert,
    delete
on public.residence_documents
to authenticated;


grant update (
    title,
    description,
    category,
    storage_bucket,
    storage_path,
    original_filename,
    mime_type,
    file_size_bytes,
    checksum_sha256,
    visible_from,
    expires_at
)
on public.residence_documents
to authenticated;



grant
    select,
    insert,
    update,
    delete
on public.residence_document_targets
to authenticated;



grant select
on public.owner_document_accesses
to authenticated;



grant all
on public.residence_documents
to service_role;


grant all
on public.residence_document_targets
to service_role;


grant all
on public.owner_document_accesses
to service_role;



-- =========================================================
-- 20. PRIVILÈGES FUNCTIONS
-- =========================================================

revoke all
on function public.owner_matches_document_target(uuid)
from public;


revoke all
on function public.owner_matches_document_target(uuid)
from anon;


grant execute
on function public.owner_matches_document_target(uuid)
to authenticated;


grant execute
on function public.owner_matches_document_target(uuid)
to service_role;



revoke all
on function public.admin_publish_residence_document(uuid)
from public;


revoke all
on function public.admin_publish_residence_document(uuid)
from anon;


grant execute
on function public.admin_publish_residence_document(uuid)
to authenticated;


grant execute
on function public.admin_publish_residence_document(uuid)
to service_role;



revoke all
on function public.admin_archive_residence_document(uuid)
from public;


revoke all
on function public.admin_archive_residence_document(uuid)
from anon;


grant execute
on function public.admin_archive_residence_document(uuid)
to authenticated;


grant execute
on function public.admin_archive_residence_document(uuid)
to service_role;



revoke all
on function public.owner_log_document_access(uuid, text)
from public;


revoke all
on function public.owner_log_document_access(uuid, text)
from anon;


grant execute
on function public.owner_log_document_access(uuid, text)
to authenticated;


grant execute
on function public.owner_log_document_access(uuid, text)
to service_role;



revoke all
on function public.admin_get_residence_document_stats(uuid)
from public;


revoke all
on function public.admin_get_residence_document_stats(uuid)
from anon;


grant execute
on function public.admin_get_residence_document_stats(uuid)
to authenticated;


grant execute
on function public.admin_get_residence_document_stats(uuid)
to service_role;
