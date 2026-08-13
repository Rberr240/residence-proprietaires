-- =========================================================
-- MIRADOR GOLF 1
-- Meetings V2 + réponses propriétaires V2
-- =========================================================


-- =========================================================
-- 1. ÉVOLUTION DE LA TABLE MEETINGS EXISTANTE
-- =========================================================

alter table public.meetings
    add column if not exists response_deadline timestamptz null;

alter table public.meetings
    add column if not exists published_at timestamptz null;

alter table public.meetings
    add column if not exists closed_at timestamptz null;

alter table public.meetings
    add column if not exists created_by uuid null
        references auth.users(id)
        on delete set null;


create index if not exists meetings_status_idx
    on public.meetings(status);

create index if not exists meetings_meeting_date_idx
    on public.meetings(meeting_date);

create index if not exists meetings_created_by_idx
    on public.meetings(created_by);


-- =========================================================
-- 2. NOUVELLE TABLE RÉPONSES V2
--
-- IMPORTANT :
-- On ne modifie PAS meeting_responses.
-- Cette ancienne table reste liée à public.owners.
-- =========================================================

create table if not exists public.owner_meeting_responses (

    id uuid primary key
        default gen_random_uuid(),

    meeting_id uuid not null
        references public.meetings(id)
        on delete cascade,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    attendance text not null,

    comment text null,

    responded_at timestamptz not null
        default now(),

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint owner_meeting_responses_attendance_check
        check (
            attendance in (
                'present',
                'absent',
                'maybe'
            )
        ),

    constraint owner_meeting_responses_unique_response
        unique (
            meeting_id,
            owner_account_id
        )

);


create index if not exists owner_meeting_responses_meeting_idx
    on public.owner_meeting_responses(meeting_id);


create index if not exists owner_meeting_responses_owner_idx
    on public.owner_meeting_responses(owner_account_id);


-- =========================================================
-- 3. UPDATED_AT AUTOMATIQUE
-- =========================================================

create or replace function public.set_owner_meeting_response_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin

    new.updated_at = now();

    new.responded_at = now();

    return new;

end;
$$;


drop trigger if exists
    owner_meeting_responses_set_updated_at
on public.owner_meeting_responses;


create trigger
    owner_meeting_responses_set_updated_at

before update
on public.owner_meeting_responses

for each row

execute function
    public.set_owner_meeting_response_updated_at();


-- =========================================================
-- 4. RLS
-- =========================================================

alter table public.meetings
    enable row level security;


alter table public.owner_meeting_responses
    enable row level security;


-- =========================================================
-- 5. POLICIES MEETINGS — ADMIN
-- =========================================================

drop policy if exists
    "meetings_v2_admin_select"
on public.meetings;


create policy
    "meetings_v2_admin_select"

on public.meetings

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "meetings_v2_admin_insert"
on public.meetings;


create policy
    "meetings_v2_admin_insert"

on public.meetings

for insert

to authenticated

with check (
    (select public.is_admin())
);


drop policy if exists
    "meetings_v2_admin_update"
on public.meetings;


create policy
    "meetings_v2_admin_update"

on public.meetings

for update

to authenticated

using (
    (select public.is_admin())
)

with check (
    (select public.is_admin())
);


drop policy if exists
    "meetings_v2_admin_delete"
on public.meetings;


create policy
    "meetings_v2_admin_delete"

on public.meetings

for delete

to authenticated

using (
    (select public.is_admin())
);


-- =========================================================
-- 6. POLICIES MEETINGS — PROPRIÉTAIRES
--
-- Un propriétaire actif peut uniquement voir
-- les réunions publiées ou terminées.
-- =========================================================

drop policy if exists
    "meetings_v2_owner_select"
on public.meetings;


create policy
    "meetings_v2_owner_select"

on public.meetings

for select

to authenticated

using (

    status in (
        'published',
        'closed'
    )

    and

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status = 'active'

    )

);


-- =========================================================
-- 7. POLICIES RESPONSES — ADMIN
-- =========================================================

drop policy if exists
    "owner_meeting_responses_admin_select"
on public.owner_meeting_responses;


create policy
    "owner_meeting_responses_admin_select"

on public.owner_meeting_responses

for select

to authenticated

using (
    (select public.is_admin())
);


-- =========================================================
-- 8. PROPRIÉTAIRE : VOIR SA PROPRE RÉPONSE
-- =========================================================

drop policy if exists
    "owner_meeting_responses_owner_select"
on public.owner_meeting_responses;


create policy
    "owner_meeting_responses_owner_select"

on public.owner_meeting_responses

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_meeting_responses.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status = 'active'

    )

);


-- =========================================================
-- 9. PROPRIÉTAIRE : CRÉER SA RÉPONSE
-- =========================================================

drop policy if exists
    "owner_meeting_responses_owner_insert"
on public.owner_meeting_responses;


create policy
    "owner_meeting_responses_owner_insert"

on public.owner_meeting_responses

for insert

to authenticated

with check (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_meeting_responses.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status = 'active'

    )

    and

    exists (

        select 1

        from public.meetings m

        where
            m.id =
                owner_meeting_responses.meeting_id

            and
            m.status = 'published'

            and (
                m.response_deadline is null
                or
                m.response_deadline > now()
            )

    )

);


-- =========================================================
-- 10. PROPRIÉTAIRE : MODIFIER SA RÉPONSE
-- =========================================================

drop policy if exists
    "owner_meeting_responses_owner_update"
on public.owner_meeting_responses;


create policy
    "owner_meeting_responses_owner_update"

on public.owner_meeting_responses

for update

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_meeting_responses.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status = 'active'

    )

)

with check (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_meeting_responses.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status = 'active'

    )

    and

    exists (

        select 1

        from public.meetings m

        where
            m.id =
                owner_meeting_responses.meeting_id

            and
            m.status = 'published'

            and (
                m.response_deadline is null
                or
                m.response_deadline > now()
            )

    )

);


-- =========================================================
-- 11. GRANTS
-- =========================================================

revoke all
on public.owner_meeting_responses
from anon;


grant
    select,
    insert,
    update
on public.owner_meeting_responses
to authenticated;


grant all
on public.owner_meeting_responses
to service_role;


grant
    select,
    insert,
    update,
    delete
on public.meetings
to authenticated;


grant all
on public.meetings
to service_role;


-- =========================================================
-- 12. RPC ADMIN : STATISTIQUES D'UNE RÉUNION
-- =========================================================

create or replace function public.admin_get_meeting_stats(
    p_meeting_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_invited integer;
    v_present integer;
    v_absent integer;
    v_maybe integer;
    v_responded integer;
    v_no_response integer;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    if not exists (

        select 1

        from public.meetings

        where id =
            p_meeting_id

    ) then

        raise exception
            'Réunion introuvable.';

    end if;


    select count(*)
    into v_invited

    from public.owner_accounts

    where status in (
        'invited',
        'active'
    );


    select count(*)
    into v_present

    from public.owner_meeting_responses

    where
        meeting_id =
            p_meeting_id

        and attendance =
            'present';


    select count(*)
    into v_absent

    from public.owner_meeting_responses

    where
        meeting_id =
            p_meeting_id

        and attendance =
            'absent';


    select count(*)
    into v_maybe

    from public.owner_meeting_responses

    where
        meeting_id =
            p_meeting_id

        and attendance =
            'maybe';


    v_responded =
        v_present
        +
        v_absent
        +
        v_maybe;


    v_no_response =
        greatest(
            v_invited - v_responded,
            0
        );


    return jsonb_build_object(

        'meetingId',
        p_meeting_id,

        'invited',
        v_invited,

        'present',
        v_present,

        'absent',
        v_absent,

        'maybe',
        v_maybe,

        'responded',
        v_responded,

        'noResponse',
        v_no_response

    );

end;
$$;


revoke all
on function public.admin_get_meeting_stats(uuid)
from public;


revoke all
on function public.admin_get_meeting_stats(uuid)
from anon;


grant execute
on function public.admin_get_meeting_stats(uuid)
to authenticated;


grant execute
on function public.admin_get_meeting_stats(uuid)
to service_role;