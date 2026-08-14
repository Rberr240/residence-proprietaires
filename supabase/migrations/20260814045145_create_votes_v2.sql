-- =========================================================
-- MIRADOR GOLF 1
-- Votes V2
-- Architecture sécurisée :
--   - votes administrés
--   - options personnalisables
--   - éligibilité figée à la publication
--   - un bulletin par propriétaire et par vote
--   - modification facultative
--   - résultats agrégés sans exposer les bulletins aux propriétaires
-- =========================================================


-- =========================================================
-- 1. TABLE PRINCIPALE : RESIDENCE_VOTES
-- =========================================================

create table if not exists public.residence_votes (

    id uuid primary key
        default gen_random_uuid(),

    title text not null,

    question text not null,

    description text null,

    status text not null
        default 'draft',

    allow_vote_change boolean not null
        default false,

    results_visibility text not null
        default 'after_close',

    opens_at timestamptz null,

    closes_at timestamptz null,

    published_at timestamptz null,

    closed_at timestamptz null,

    cancelled_at timestamptz null,

    created_by uuid null
        references auth.users(id)
        on delete set null,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint residence_votes_title_not_blank
        check (
            length(trim(title)) > 0
        ),

    constraint residence_votes_question_not_blank
        check (
            length(trim(question)) > 0
        ),

    constraint residence_votes_status_check
        check (
            status in (
                'draft',
                'published',
                'closed',
                'cancelled'
            )
        ),

    constraint residence_votes_results_visibility_check
        check (
            results_visibility in (
                'admin_only',
                'after_close',
                'live'
            )
        ),

    constraint residence_votes_dates_check
        check (
            opens_at is null
            or closes_at is null
            or closes_at > opens_at
        )
);


create index if not exists
    residence_votes_status_idx
on public.residence_votes(status);


create index if not exists
    residence_votes_opens_at_idx
on public.residence_votes(opens_at);


create index if not exists
    residence_votes_closes_at_idx
on public.residence_votes(closes_at);


create index if not exists
    residence_votes_created_by_idx
on public.residence_votes(created_by);



-- =========================================================
-- 2. OPTIONS DE VOTE
-- =========================================================

create table if not exists public.residence_vote_options (

    id uuid primary key
        default gen_random_uuid(),

    vote_id uuid not null
        references public.residence_votes(id)
        on delete cascade,

    label text not null,

    description text null,

    position integer not null
        default 0,

    created_at timestamptz not null
        default now(),

    constraint residence_vote_options_label_not_blank
        check (
            length(trim(label)) > 0
        ),

    constraint residence_vote_options_position_check
        check (
            position >= 0
        ),

    constraint residence_vote_options_vote_position_unique
        unique (
            vote_id,
            position
        ),

    constraint residence_vote_options_vote_id_id_unique
        unique (
            vote_id,
            id
        )
);


create index if not exists
    residence_vote_options_vote_idx
on public.residence_vote_options(vote_id);



-- =========================================================
-- 3. ÉLIGIBILITÉ
--
-- Cette table est remplie au moment de la publication.
-- Le nombre d'éligibles ne change donc pas si de nouveaux
-- comptes sont activés après la publication du vote.
--
-- voting_weight = 1 pour l'instant.
-- Il permettra plus tard d'intégrer des tantièmes / quotes-parts
-- sans casser l'architecture.
-- =========================================================

create table if not exists public.residence_vote_eligibility (

    id uuid primary key
        default gen_random_uuid(),

    vote_id uuid not null
        references public.residence_votes(id)
        on delete cascade,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    voting_weight numeric(14,4) not null
        default 1,

    created_at timestamptz not null
        default now(),

    constraint residence_vote_eligibility_weight_check
        check (
            voting_weight > 0
        ),

    constraint residence_vote_eligibility_unique
        unique (
            vote_id,
            owner_account_id
        )
);


create index if not exists
    residence_vote_eligibility_vote_idx
on public.residence_vote_eligibility(vote_id);


create index if not exists
    residence_vote_eligibility_owner_idx
on public.residence_vote_eligibility(owner_account_id);



-- =========================================================
-- 4. BULLETINS PROPRIÉTAIRES
--
-- Un seul bulletin par propriétaire et par vote.
--
-- Les deux FK composites garantissent :
--   - que le propriétaire est réellement éligible ;
--   - que l'option appartient réellement au même vote.
-- =========================================================

create table if not exists public.owner_vote_ballots (

    id uuid primary key
        default gen_random_uuid(),

    vote_id uuid not null,

    owner_account_id uuid not null,

    option_id uuid not null,

    submitted_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint owner_vote_ballots_unique_vote
        unique (
            vote_id,
            owner_account_id
        ),

    constraint owner_vote_ballots_eligibility_fkey
        foreign key (
            vote_id,
            owner_account_id
        )
        references public.residence_vote_eligibility(
            vote_id,
            owner_account_id
        )
        on delete cascade,

    constraint owner_vote_ballots_option_fkey
        foreign key (
            vote_id,
            option_id
        )
        references public.residence_vote_options(
            vote_id,
            id
        )
        on delete restrict
);


create index if not exists
    owner_vote_ballots_vote_idx
on public.owner_vote_ballots(vote_id);


create index if not exists
    owner_vote_ballots_owner_idx
on public.owner_vote_ballots(owner_account_id);


create index if not exists
    owner_vote_ballots_option_idx
on public.owner_vote_ballots(option_id);



-- =========================================================
-- 5. UPDATED_AT AUTOMATIQUE
-- =========================================================

create or replace function public.set_residence_vote_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin

    new.updated_at = now();

    return new;

end;
$$;


drop trigger if exists
    residence_votes_set_updated_at
on public.residence_votes;


create trigger
    residence_votes_set_updated_at

before update
on public.residence_votes

for each row

execute function
    public.set_residence_vote_updated_at();



-- =========================================================
-- 6. VALIDATION SERVEUR DES BULLETINS
--
-- Défense en profondeur :
-- même si une requête contourne accidentellement le frontend,
-- PostgreSQL refuse un bulletin hors période ou une modification
-- interdite.
-- =========================================================

create or replace function public.validate_owner_vote_ballot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare

    v_vote public.residence_votes%rowtype;

begin

    select *
    into v_vote

    from public.residence_votes

    where id =
        new.vote_id;


    if not found then

        raise exception
            'Vote introuvable.';

    end if;


    if tg_op = 'UPDATE' then

        if
            new.vote_id <>
            old.vote_id
            or
            new.owner_account_id <>
            old.owner_account_id
        then

            raise exception
                'Le vote ou le propriétaire du bulletin ne peut pas être modifié.';

        end if;


        if not v_vote.allow_vote_change then

            raise exception
                'Ce vote est définitif après confirmation.';

        end if;

    end if;


    if v_vote.status <> 'published' then

        raise exception
            'Ce vote n''est pas ouvert.';

    end if;


    if
        v_vote.opens_at is not null
        and
        v_vote.opens_at > now()
    then

        raise exception
            'Ce vote n''est pas encore ouvert.';

    end if;


    if
        v_vote.closes_at is not null
        and
        v_vote.closes_at <= now()
    then

        raise exception
            'La période de vote est terminée.';

    end if;


    if not exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                new.owner_account_id

            and
            oa.status =
                'active'

    ) then

        raise exception
            'Compte propriétaire non actif.';

    end if;


    if tg_op = 'INSERT' then

        new.submitted_at =
            coalesce(
                new.submitted_at,
                now()
            );

    end if;


    new.updated_at =
        now();


    return new;

end;
$$;


drop trigger if exists
    owner_vote_ballots_validate
on public.owner_vote_ballots;


create trigger
    owner_vote_ballots_validate

before insert or update
on public.owner_vote_ballots

for each row

execute function
    public.validate_owner_vote_ballot();



-- =========================================================
-- 7. RLS
-- =========================================================

alter table public.residence_votes
    enable row level security;


alter table public.residence_vote_options
    enable row level security;


alter table public.residence_vote_eligibility
    enable row level security;


alter table public.owner_vote_ballots
    enable row level security;



-- =========================================================
-- 8. RESIDENCE_VOTES — ADMIN
-- =========================================================

drop policy if exists
    "residence_votes_admin_select"
on public.residence_votes;


create policy
    "residence_votes_admin_select"

on public.residence_votes

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_votes_admin_insert"
on public.residence_votes;


create policy
    "residence_votes_admin_insert"

on public.residence_votes

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    status = 'draft'

);


drop policy if exists
    "residence_votes_admin_update"
on public.residence_votes;


create policy
    "residence_votes_admin_update"

on public.residence_votes

for update

to authenticated

using (
    (select public.is_admin())
)

with check (
    (select public.is_admin())
);


drop policy if exists
    "residence_votes_admin_delete"
on public.residence_votes;


create policy
    "residence_votes_admin_delete"

on public.residence_votes

for delete

to authenticated

using (

    (select public.is_admin())

    and

    status = 'draft'

);



-- =========================================================
-- 9. RESIDENCE_VOTES — PROPRIÉTAIRE
--
-- Le propriétaire voit uniquement les votes pour lesquels
-- son compte a été figé comme éligible à la publication.
-- =========================================================

drop policy if exists
    "residence_votes_owner_select"
on public.residence_votes;


create policy
    "residence_votes_owner_select"

on public.residence_votes

for select

to authenticated

using (

    status in (
        'published',
        'closed',
        'cancelled'
    )

    and

    exists (

        select 1

        from public.residence_vote_eligibility e

        join public.owner_accounts oa
            on oa.id =
                e.owner_account_id

        where
            e.vote_id =
                residence_votes.id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 10. OPTIONS — ADMIN
--
-- Les options sont modifiables uniquement tant que le vote
-- est encore en brouillon.
-- =========================================================

drop policy if exists
    "residence_vote_options_admin_select"
on public.residence_vote_options;


create policy
    "residence_vote_options_admin_select"

on public.residence_vote_options

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "residence_vote_options_admin_insert"
on public.residence_vote_options;


create policy
    "residence_vote_options_admin_insert"

on public.residence_vote_options

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                residence_vote_options.vote_id

            and
            v.status =
                'draft'

    )

);


drop policy if exists
    "residence_vote_options_admin_update"
on public.residence_vote_options;


create policy
    "residence_vote_options_admin_update"

on public.residence_vote_options

for update

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                residence_vote_options.vote_id

            and
            v.status =
                'draft'

    )

)

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                residence_vote_options.vote_id

            and
            v.status =
                'draft'

    )

);


drop policy if exists
    "residence_vote_options_admin_delete"
on public.residence_vote_options;


create policy
    "residence_vote_options_admin_delete"

on public.residence_vote_options

for delete

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                residence_vote_options.vote_id

            and
            v.status =
                'draft'

    )

);



-- =========================================================
-- 11. OPTIONS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "residence_vote_options_owner_select"
on public.residence_vote_options;


create policy
    "residence_vote_options_owner_select"

on public.residence_vote_options

for select

to authenticated

using (

    exists (

        select 1

        from public.residence_votes v

        join public.residence_vote_eligibility e
            on e.vote_id =
                v.id

        join public.owner_accounts oa
            on oa.id =
                e.owner_account_id

        where
            v.id =
                residence_vote_options.vote_id

            and
            v.status in (
                'published',
                'closed',
                'cancelled'
            )

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 12. ÉLIGIBILITÉ — ADMIN
-- =========================================================

drop policy if exists
    "residence_vote_eligibility_admin_select"
on public.residence_vote_eligibility;


create policy
    "residence_vote_eligibility_admin_select"

on public.residence_vote_eligibility

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 13. ÉLIGIBILITÉ — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "residence_vote_eligibility_owner_select"
on public.residence_vote_eligibility;


create policy
    "residence_vote_eligibility_owner_select"

on public.residence_vote_eligibility

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                residence_vote_eligibility.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 14. BULLETINS — ADMIN
--
-- L'admin peut consulter les bulletins pour le suivi et
-- les statistiques, mais ne dispose d'aucune policy
-- INSERT / UPDATE / DELETE sur les bulletins propriétaires.
-- =========================================================

drop policy if exists
    "owner_vote_ballots_admin_select"
on public.owner_vote_ballots;


create policy
    "owner_vote_ballots_admin_select"

on public.owner_vote_ballots

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 15. BULLETINS — PROPRIÉTAIRE : LECTURE
-- =========================================================

drop policy if exists
    "owner_vote_ballots_owner_select"
on public.owner_vote_ballots;


create policy
    "owner_vote_ballots_owner_select"

on public.owner_vote_ballots

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_vote_ballots.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 16. BULLETINS — PROPRIÉTAIRE : PREMIER VOTE
-- =========================================================

drop policy if exists
    "owner_vote_ballots_owner_insert"
on public.owner_vote_ballots;


create policy
    "owner_vote_ballots_owner_insert"

on public.owner_vote_ballots

for insert

to authenticated

with check (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_vote_ballots.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

    and

    exists (

        select 1

        from public.residence_vote_eligibility e

        where
            e.vote_id =
                owner_vote_ballots.vote_id

            and
            e.owner_account_id =
                owner_vote_ballots.owner_account_id

    )

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                owner_vote_ballots.vote_id

            and
            v.status =
                'published'

            and (
                v.opens_at is null
                or
                v.opens_at <= now()
            )

            and (
                v.closes_at is null
                or
                v.closes_at > now()
            )

    )

);



-- =========================================================
-- 17. BULLETINS — PROPRIÉTAIRE : MODIFICATION
--
-- Si allow_vote_change = false, aucune modification ne passe.
-- =========================================================

drop policy if exists
    "owner_vote_ballots_owner_update"
on public.owner_vote_ballots;


create policy
    "owner_vote_ballots_owner_update"

on public.owner_vote_ballots

for update

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_vote_ballots.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

)

with check (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_vote_ballots.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

    and

    exists (

        select 1

        from public.residence_votes v

        where
            v.id =
                owner_vote_ballots.vote_id

            and
            v.status =
                'published'

            and
            v.allow_vote_change =
                true

            and (
                v.opens_at is null
                or
                v.opens_at <= now()
            )

            and (
                v.closes_at is null
                or
                v.closes_at > now()
            )

    )

);



-- =========================================================
-- 18. RPC ADMIN : PUBLICATION
--
-- La publication :
--   1. verrouille le vote ;
--   2. vérifie qu'il est en brouillon ;
--   3. vérifie qu'il possède au moins 2 options ;
--   4. valide la période ;
--   5. fige la liste des propriétaires actifs éligibles ;
--   6. passe le vote à published.
-- =========================================================

create or replace function public.admin_publish_residence_vote(
    p_vote_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_vote public.residence_votes%rowtype;

    v_option_count integer;

    v_eligible_count integer;

    v_effective_opens_at timestamptz;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_vote

    from public.residence_votes

    where id =
        p_vote_id

    for update;


    if not found then

        raise exception
            'Vote introuvable.';

    end if;


    if v_vote.status <> 'draft' then

        raise exception
            'Seul un brouillon peut être publié.';

    end if;


    select count(*)
    into v_option_count

    from public.residence_vote_options

    where vote_id =
        p_vote_id;


    if v_option_count < 2 then

        raise exception
            'Le vote doit contenir au moins deux options.';

    end if;


    v_effective_opens_at =
        coalesce(
            v_vote.opens_at,
            now()
        );


    if v_vote.closes_at is null then

        raise exception
            'Une date de clôture est obligatoire avant publication.';

    end if;


    if
        v_vote.closes_at <=
        v_effective_opens_at
    then

        raise exception
            'La date de clôture doit être postérieure à la date d''ouverture.';

    end if;


    delete from public.residence_vote_eligibility

    where vote_id =
        p_vote_id;


    insert into public.residence_vote_eligibility (
        vote_id,
        owner_account_id,
        voting_weight
    )

    select
        p_vote_id,
        oa.id,
        1

    from public.owner_accounts oa

    where oa.status =
        'active';


    get diagnostics
        v_eligible_count =
        row_count;


    if v_eligible_count = 0 then

        raise exception
            'Aucun propriétaire actif n''est éligible à ce vote.';

    end if;


    update public.residence_votes

    set
        status =
            'published',

        opens_at =
            v_effective_opens_at,

        published_at =
            now(),

        closed_at =
            null,

        cancelled_at =
            null

    where id =
        p_vote_id;


    return jsonb_build_object(

        'success',
        true,

        'voteId',
        p_vote_id,

        'status',
        'published',

        'optionCount',
        v_option_count,

        'eligibleCount',
        v_eligible_count,

        'opensAt',
        v_effective_opens_at,

        'closesAt',
        v_vote.closes_at

    );

end;
$$;



-- =========================================================
-- 19. RPC ADMIN : CLÔTURE
-- =========================================================

create or replace function public.admin_close_residence_vote(
    p_vote_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_vote public.residence_votes%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_vote

    from public.residence_votes

    where id =
        p_vote_id

    for update;


    if not found then

        raise exception
            'Vote introuvable.';

    end if;


    if v_vote.status <> 'published' then

        raise exception
            'Seul un vote publié peut être clôturé.';

    end if;


    update public.residence_votes

    set
        status =
            'closed',

        closed_at =
            now()

    where id =
        p_vote_id;


    return jsonb_build_object(

        'success',
        true,

        'voteId',
        p_vote_id,

        'status',
        'closed',

        'closedAt',
        now()

    );

end;
$$;



-- =========================================================
-- 20. RPC ADMIN : ANNULATION D'UN VOTE PUBLIÉ
-- =========================================================

create or replace function public.admin_cancel_residence_vote(
    p_vote_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_vote public.residence_votes%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_vote

    from public.residence_votes

    where id =
        p_vote_id

    for update;


    if not found then

        raise exception
            'Vote introuvable.';

    end if;


    if v_vote.status <> 'published' then

        raise exception
            'Seul un vote publié peut être annulé.';

    end if;


    update public.residence_votes

    set
        status =
            'cancelled',

        cancelled_at =
            now()

    where id =
        p_vote_id;


    return jsonb_build_object(

        'success',
        true,

        'voteId',
        p_vote_id,

        'status',
        'cancelled',

        'cancelledAt',
        now()

    );

end;
$$;



-- =========================================================
-- 21. RPC ADMIN : STATISTIQUES AGRÉGÉES
-- =========================================================

create or replace function public.admin_get_residence_vote_stats(
    p_vote_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_eligible integer;

    v_votes_cast integer;

    v_no_vote integer;

    v_eligible_weight numeric;

    v_cast_weight numeric;

    v_options jsonb;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    if not exists (

        select 1

        from public.residence_votes

        where id =
            p_vote_id

    ) then

        raise exception
            'Vote introuvable.';

    end if;


    select
        count(*),
        coalesce(
            sum(voting_weight),
            0
        )

    into
        v_eligible,
        v_eligible_weight

    from public.residence_vote_eligibility

    where vote_id =
        p_vote_id;


    select
        count(*),
        coalesce(
            sum(e.voting_weight),
            0
        )

    into
        v_votes_cast,
        v_cast_weight

    from public.owner_vote_ballots b

    join public.residence_vote_eligibility e
        on
            e.vote_id =
                b.vote_id

            and
            e.owner_account_id =
                b.owner_account_id

    where b.vote_id =
        p_vote_id;


    v_no_vote =
        greatest(
            v_eligible -
            v_votes_cast,
            0
        );


    select
        coalesce(
            jsonb_agg(

                jsonb_build_object(

                    'optionId',
                    o.id,

                    'label',
                    o.label,

                    'position',
                    o.position,

                    'votes',
                    coalesce(
                        s.vote_count,
                        0
                    ),

                    'weightedVotes',
                    coalesce(
                        s.weighted_votes,
                        0
                    ),

                    'percentage',
                    case

                        when
                            v_votes_cast > 0

                        then
                            round(
                                (
                                    coalesce(
                                        s.vote_count,
                                        0
                                    )::numeric
                                    *
                                    100
                                )
                                /
                                v_votes_cast,
                                2
                            )

                        else
                            0

                    end,

                    'weightedPercentage',
                    case

                        when
                            v_cast_weight > 0

                        then
                            round(
                                (
                                    coalesce(
                                        s.weighted_votes,
                                        0
                                    )
                                    *
                                    100
                                )
                                /
                                v_cast_weight,
                                2
                            )

                        else
                            0

                    end

                )

                order by
                    o.position,
                    o.created_at

            ),
            '[]'::jsonb
        )

    into v_options

    from public.residence_vote_options o

    left join (

        select

            b.option_id,

            count(*) as
                vote_count,

            coalesce(
                sum(e.voting_weight),
                0
            ) as
                weighted_votes

        from public.owner_vote_ballots b

        join public.residence_vote_eligibility e
            on
                e.vote_id =
                    b.vote_id

                and
                e.owner_account_id =
                    b.owner_account_id

        where b.vote_id =
            p_vote_id

        group by
            b.option_id

    ) s
        on s.option_id =
            o.id

    where o.vote_id =
        p_vote_id;


    return jsonb_build_object(

        'voteId',
        p_vote_id,

        'eligible',
        v_eligible,

        'votesCast',
        v_votes_cast,

        'noVote',
        v_no_vote,

        'eligibleWeight',
        v_eligible_weight,

        'castWeight',
        v_cast_weight,

        'options',
        v_options

    );

end;
$$;



-- =========================================================
-- 22. RPC PROPRIÉTAIRE : RÉSULTATS AGRÉGÉS
--
-- Cette fonction n'expose jamais :
--   - owner_account_id des autres propriétaires ;
--   - les bulletins individuels ;
--   - l'identité des votants.
--
-- Elle respecte results_visibility :
--   admin_only  -> jamais visible au propriétaire
--   after_close -> visible après clôture / échéance
--   live        -> visible pendant et après le vote
-- =========================================================

create or replace function public.owner_get_residence_vote_results(
    p_vote_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_vote public.residence_votes%rowtype;

    v_owner_account_id uuid;

    v_votes_cast integer;

    v_cast_weight numeric;

    v_options jsonb;

begin

    select *
    into v_vote

    from public.residence_votes

    where id =
        p_vote_id;


    if not found then

        raise exception
            'Vote introuvable.';

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


    if v_owner_account_id is null then

        raise exception
            'Compte propriétaire actif requis.';

    end if;


    if not exists (

        select 1

        from public.residence_vote_eligibility e

        where
            e.vote_id =
                p_vote_id

            and
            e.owner_account_id =
                v_owner_account_id

    ) then

        raise exception
            'Vous n''êtes pas éligible à ce vote.';

    end if;


    if
        v_vote.results_visibility =
        'admin_only'
    then

        raise exception
            'Les résultats ne sont pas accessibles aux propriétaires.';

    end if;


    if
        v_vote.results_visibility =
        'after_close'

        and not (

            v_vote.status =
            'closed'

            or (

                v_vote.closes_at is not null

                and

                v_vote.closes_at <= now()

            )

        )
    then

        raise exception
            'Les résultats seront disponibles après la clôture.';

    end if;


    select
        count(*),
        coalesce(
            sum(e.voting_weight),
            0
        )

    into
        v_votes_cast,
        v_cast_weight

    from public.owner_vote_ballots b

    join public.residence_vote_eligibility e
        on
            e.vote_id =
                b.vote_id

            and
            e.owner_account_id =
                b.owner_account_id

    where b.vote_id =
        p_vote_id;


    select
        coalesce(
            jsonb_agg(

                jsonb_build_object(

                    'optionId',
                    o.id,

                    'label',
                    o.label,

                    'position',
                    o.position,

                    'votes',
                    coalesce(
                        s.vote_count,
                        0
                    ),

                    'weightedVotes',
                    coalesce(
                        s.weighted_votes,
                        0
                    ),

                    'percentage',
                    case

                        when
                            v_votes_cast > 0

                        then
                            round(
                                (
                                    coalesce(
                                        s.vote_count,
                                        0
                                    )::numeric
                                    *
                                    100
                                )
                                /
                                v_votes_cast,
                                2
                            )

                        else
                            0

                    end,

                    'weightedPercentage',
                    case

                        when
                            v_cast_weight > 0

                        then
                            round(
                                (
                                    coalesce(
                                        s.weighted_votes,
                                        0
                                    )
                                    *
                                    100
                                )
                                /
                                v_cast_weight,
                                2
                            )

                        else
                            0

                    end

                )

                order by
                    o.position,
                    o.created_at

            ),
            '[]'::jsonb
        )

    into v_options

    from public.residence_vote_options o

    left join (

        select

            b.option_id,

            count(*) as
                vote_count,

            coalesce(
                sum(e.voting_weight),
                0
            ) as
                weighted_votes

        from public.owner_vote_ballots b

        join public.residence_vote_eligibility e
            on
                e.vote_id =
                    b.vote_id

                and
                e.owner_account_id =
                    b.owner_account_id

        where b.vote_id =
            p_vote_id

        group by
            b.option_id

    ) s
        on s.option_id =
            o.id

    where o.vote_id =
        p_vote_id;


    return jsonb_build_object(

        'voteId',
        p_vote_id,

        'votesCast',
        v_votes_cast,

        'castWeight',
        v_cast_weight,

        'options',
        v_options

    );

end;
$$;



-- =========================================================
-- 23. PRIVILÈGES TABLES
-- =========================================================

revoke all
on public.residence_votes
from anon;


revoke all
on public.residence_vote_options
from anon;


revoke all
on public.residence_vote_eligibility
from anon;


revoke all
on public.owner_vote_ballots
from anon;



-- Vote principal :
-- les propriétaires peuvent SELECT grâce à RLS.
-- INSERT/UPDATE/DELETE restent utilisables uniquement par
-- l'admin grâce aux policies.
grant
    select,
    insert,
    delete
on public.residence_votes
to authenticated;


grant update (
    title,
    question,
    description,
    opens_at,
    closes_at,
    allow_vote_change,
    results_visibility
)
on public.residence_votes
to authenticated;



-- Options :
-- admin CRUD en brouillon ;
-- propriétaire SELECT uniquement via RLS.
grant
    select,
    insert,
    update,
    delete
on public.residence_vote_options
to authenticated;



-- Éligibilité :
-- lecture uniquement.
grant select
on public.residence_vote_eligibility
to authenticated;



-- Bulletins :
-- propriétaires INSERT ;
-- UPDATE uniquement sur l'option choisie.
-- admin dispose uniquement de SELECT via RLS.
grant
    select,
    insert
on public.owner_vote_ballots
to authenticated;


grant update (
    option_id
)
on public.owner_vote_ballots
to authenticated;



grant all
on public.residence_votes
to service_role;


grant all
on public.residence_vote_options
to service_role;


grant all
on public.residence_vote_eligibility
to service_role;


grant all
on public.owner_vote_ballots
to service_role;



-- =========================================================
-- 24. PRIVILÈGES FUNCTIONS
-- =========================================================

revoke all
on function public.admin_publish_residence_vote(uuid)
from public;


revoke all
on function public.admin_publish_residence_vote(uuid)
from anon;


grant execute
on function public.admin_publish_residence_vote(uuid)
to authenticated;


grant execute
on function public.admin_publish_residence_vote(uuid)
to service_role;



revoke all
on function public.admin_close_residence_vote(uuid)
from public;


revoke all
on function public.admin_close_residence_vote(uuid)
from anon;


grant execute
on function public.admin_close_residence_vote(uuid)
to authenticated;


grant execute
on function public.admin_close_residence_vote(uuid)
to service_role;



revoke all
on function public.admin_cancel_residence_vote(uuid)
from public;


revoke all
on function public.admin_cancel_residence_vote(uuid)
from anon;


grant execute
on function public.admin_cancel_residence_vote(uuid)
to authenticated;


grant execute
on function public.admin_cancel_residence_vote(uuid)
to service_role;



revoke all
on function public.admin_get_residence_vote_stats(uuid)
from public;


revoke all
on function public.admin_get_residence_vote_stats(uuid)
from anon;


grant execute
on function public.admin_get_residence_vote_stats(uuid)
to authenticated;


grant execute
on function public.admin_get_residence_vote_stats(uuid)
to service_role;



revoke all
on function public.owner_get_residence_vote_results(uuid)
from public;


revoke all
on function public.owner_get_residence_vote_results(uuid)
from anon;


grant execute
on function public.owner_get_residence_vote_results(uuid)
to authenticated;


grant execute
on function public.owner_get_residence_vote_results(uuid)
to service_role;
