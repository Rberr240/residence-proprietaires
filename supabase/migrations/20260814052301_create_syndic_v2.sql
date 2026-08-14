-- =========================================================
-- MIRADOR GOLF 1
-- SYNDIC V2
--
-- Architecture comptable sécurisée :
--   - appels de fonds
--   - créances figées par lot à la publication
--   - paiements administratifs
--   - ventilation des paiements
--   - paiements partiels
--   - ajustements par lot
--   - historique et annulation comptable sans suppression
--   - RLS propriétaire / administrateur
--   - statistiques Admin
--   - synthèse propriétaire
--
-- IMPORTANT :
-- Les montants sont rattachés aux LOTS (owner_account_units),
-- et non uniquement au compte propriétaire.
-- Cela permet à un propriétaire possédant plusieurs lots
-- d'avoir une situation correcte par appartement.
-- =========================================================


-- =========================================================
-- 1. APPELS DE FONDS
-- =========================================================

create table if not exists public.syndic_charge_calls (

    id uuid primary key
        default gen_random_uuid(),

    title text not null,

    description text null,

    fiscal_year integer not null,

    period_label text null,

    charge_type text not null
        default 'regular',

    default_amount numeric(14,2) not null,

    currency text not null
        default 'MAD',

    due_date date not null,

    status text not null
        default 'draft',

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

    constraint syndic_charge_calls_title_not_blank
        check (
            length(trim(title)) > 0
        ),

    constraint syndic_charge_calls_fiscal_year_check
        check (
            fiscal_year between 2000 and 2200
        ),

    constraint syndic_charge_calls_type_check
        check (
            charge_type in (
                'regular',
                'exceptional',
                'adjustment',
                'other'
            )
        ),

    constraint syndic_charge_calls_default_amount_check
        check (
            default_amount > 0
        ),

    constraint syndic_charge_calls_currency_check
        check (
            length(trim(currency)) = 3
        ),

    constraint syndic_charge_calls_status_check
        check (
            status in (
                'draft',
                'published',
                'closed',
                'cancelled'
            )
        )
);


create index if not exists
    syndic_charge_calls_status_idx
on public.syndic_charge_calls(status);


create index if not exists
    syndic_charge_calls_due_date_idx
on public.syndic_charge_calls(due_date);


create index if not exists
    syndic_charge_calls_fiscal_year_idx
on public.syndic_charge_calls(fiscal_year);


create index if not exists
    syndic_charge_calls_created_by_idx
on public.syndic_charge_calls(created_by);



-- =========================================================
-- 2. CRÉANCES PAR LOT
--
-- Une ligne est créée pour chaque lot au moment où l'appel
-- de fonds est publié.
--
-- owner_account_id, building_code et apartment_number sont
-- volontairement copiés en snapshot afin de préserver
-- l'historique même si le rattachement du lot évolue plus tard.
--
-- amount_due est une colonne générée :
--   base_amount + adjustment_amount
-- =========================================================

create table if not exists public.syndic_unit_charges (

    id uuid primary key
        default gen_random_uuid(),

    charge_call_id uuid not null
        references public.syndic_charge_calls(id)
        on delete cascade,

    owner_account_unit_id uuid not null
        references public.owner_account_units(id)
        on delete restrict,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete restrict,

    building_code text not null,

    apartment_number text not null,

    base_amount numeric(14,2) not null,

    adjustment_amount numeric(14,2) not null
        default 0,

    adjustment_note text null,

    amount_due numeric(14,2)
        generated always as (
            base_amount + adjustment_amount
        ) stored,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint syndic_unit_charges_base_amount_check
        check (
            base_amount >= 0
        ),

    constraint syndic_unit_charges_total_check
        check (
            base_amount + adjustment_amount >= 0
        ),

    constraint syndic_unit_charges_unique
        unique (
            charge_call_id,
            owner_account_unit_id
        )
);


create index if not exists
    syndic_unit_charges_call_idx
on public.syndic_unit_charges(charge_call_id);


create index if not exists
    syndic_unit_charges_owner_idx
on public.syndic_unit_charges(owner_account_id);


create index if not exists
    syndic_unit_charges_unit_idx
on public.syndic_unit_charges(owner_account_unit_id);



-- =========================================================
-- 3. PAIEMENTS
--
-- Aucun paiement confirmé n'est supprimé.
-- Une correction se fait par statut "reversed".
-- =========================================================

create table if not exists public.syndic_payments (

    id uuid primary key
        default gen_random_uuid(),

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete restrict,

    payment_date date not null,

    amount numeric(14,2) not null,

    currency text not null
        default 'MAD',

    payment_method text not null,

    reference text null,

    notes text null,

    receipt_storage_path text null,

    status text not null
        default 'confirmed',

    recorded_by uuid null
        references auth.users(id)
        on delete set null,

    confirmed_at timestamptz null
        default now(),

    reversed_at timestamptz null,

    reversed_by uuid null
        references auth.users(id)
        on delete set null,

    reversal_reason text null,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint syndic_payments_amount_check
        check (
            amount > 0
        ),

    constraint syndic_payments_currency_check
        check (
            length(trim(currency)) = 3
        ),

    constraint syndic_payments_method_check
        check (
            payment_method in (
                'bank_transfer',
                'cash',
                'cheque',
                'card',
                'other'
            )
        ),

    constraint syndic_payments_status_check
        check (
            status in (
                'pending',
                'confirmed',
                'rejected',
                'reversed'
            )
        )
);


create index if not exists
    syndic_payments_owner_idx
on public.syndic_payments(owner_account_id);


create index if not exists
    syndic_payments_date_idx
on public.syndic_payments(payment_date);


create index if not exists
    syndic_payments_status_idx
on public.syndic_payments(status);



-- =========================================================
-- 4. VENTILATION DES PAIEMENTS
--
-- Un paiement peut couvrir plusieurs créances.
-- Une créance peut être réglée en plusieurs paiements.
-- =========================================================

create table if not exists public.syndic_payment_allocations (

    id uuid primary key
        default gen_random_uuid(),

    payment_id uuid not null
        references public.syndic_payments(id)
        on delete restrict,

    unit_charge_id uuid not null
        references public.syndic_unit_charges(id)
        on delete restrict,

    amount numeric(14,2) not null,

    created_at timestamptz not null
        default now(),

    constraint syndic_payment_allocations_amount_check
        check (
            amount > 0
        ),

    constraint syndic_payment_allocations_unique
        unique (
            payment_id,
            unit_charge_id
        )
);


create index if not exists
    syndic_payment_allocations_payment_idx
on public.syndic_payment_allocations(payment_id);


create index if not exists
    syndic_payment_allocations_charge_idx
on public.syndic_payment_allocations(unit_charge_id);



-- =========================================================
-- 5. UPDATED_AT
-- =========================================================

create or replace function public.set_syndic_updated_at()
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
    syndic_charge_calls_set_updated_at
on public.syndic_charge_calls;


create trigger
    syndic_charge_calls_set_updated_at

before update
on public.syndic_charge_calls

for each row

execute function
    public.set_syndic_updated_at();


drop trigger if exists
    syndic_unit_charges_set_updated_at
on public.syndic_unit_charges;


create trigger
    syndic_unit_charges_set_updated_at

before update
on public.syndic_unit_charges

for each row

execute function
    public.set_syndic_updated_at();


drop trigger if exists
    syndic_payments_set_updated_at
on public.syndic_payments;


create trigger
    syndic_payments_set_updated_at

before update
on public.syndic_payments

for each row

execute function
    public.set_syndic_updated_at();



-- =========================================================
-- 6. VALIDATION DES VENTILATIONS
--
-- Défense en profondeur :
--   - le paiement et la créance doivent appartenir au même
--     propriétaire ;
--   - les allocations d'un paiement ne peuvent pas dépasser
--     son montant ;
--   - une créance ne peut pas être surpayée.
-- =========================================================

create or replace function public.validate_syndic_payment_allocation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare

    v_payment public.syndic_payments%rowtype;

    v_charge public.syndic_unit_charges%rowtype;

    v_payment_allocated numeric(14,2);

    v_charge_paid numeric(14,2);

begin

    select *
    into v_payment

    from public.syndic_payments

    where id =
        new.payment_id;


    if not found then

        raise exception
            'Paiement introuvable.';

    end if;


    select *
    into v_charge

    from public.syndic_unit_charges

    where id =
        new.unit_charge_id;


    if not found then

        raise exception
            'Créance introuvable.';

    end if;


    if
        v_payment.owner_account_id <>
        v_charge.owner_account_id
    then

        raise exception
            'Le paiement et la créance n''appartiennent pas au même propriétaire.';

    end if;


    if
        v_payment.status not in (
            'pending',
            'confirmed'
        )
    then

        raise exception
            'Ce paiement ne peut plus être ventilé.';

    end if;


    select
        coalesce(
            sum(a.amount),
            0
        )

    into v_payment_allocated

    from public.syndic_payment_allocations a

    where
        a.payment_id =
            new.payment_id

        and (
            tg_op <> 'UPDATE'
            or
            a.id <>
                new.id
        );


    if
        v_payment_allocated +
        new.amount >
        v_payment.amount
    then

        raise exception
            'Les ventilations dépassent le montant du paiement.';

    end if;


    select
        coalesce(
            sum(a.amount),
            0
        )

    into v_charge_paid

    from public.syndic_payment_allocations a

    join public.syndic_payments p
        on p.id =
            a.payment_id

    where
        a.unit_charge_id =
            new.unit_charge_id

        and
        p.status =
            'confirmed'

        and (
            tg_op <> 'UPDATE'
            or
            a.id <>
                new.id
        );


    if
        v_payment.status =
            'confirmed'

        and

        v_charge_paid +
        new.amount >
        v_charge.amount_due
    then

        raise exception
            'Cette ventilation dépasserait le montant restant dû.';

    end if;


    return new;

end;
$$;


drop trigger if exists
    syndic_payment_allocations_validate
on public.syndic_payment_allocations;


create trigger
    syndic_payment_allocations_validate

before insert or update
on public.syndic_payment_allocations

for each row

execute function
    public.validate_syndic_payment_allocation();



-- =========================================================
-- 7. PROTECTION DES AJUSTEMENTS DE CRÉANCE
--
-- Une réduction manuelle ne peut jamais faire passer
-- le montant dû sous le total des paiements confirmés.
-- =========================================================

create or replace function public.validate_syndic_unit_charge_adjustment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare

    v_confirmed_paid numeric(14,2);

begin

    select
        coalesce(
            sum(a.amount),
            0
        )

    into v_confirmed_paid

    from public.syndic_payment_allocations a

    join public.syndic_payments p
        on p.id =
            a.payment_id

    where
        a.unit_charge_id =
            old.id

        and
        p.status =
            'confirmed';


    if
        new.base_amount +
        new.adjustment_amount <
        v_confirmed_paid
    then

        raise exception
            'Le nouveau montant dû ne peut pas être inférieur au montant déjà encaissé.';

    end if;


    return new;

end;
$$;


drop trigger if exists
    syndic_unit_charges_validate_adjustment
on public.syndic_unit_charges;


create trigger
    syndic_unit_charges_validate_adjustment

before update
on public.syndic_unit_charges

for each row

execute function
    public.validate_syndic_unit_charge_adjustment();



-- =========================================================
-- 8. RLS
-- =========================================================

alter table public.syndic_charge_calls
    enable row level security;


alter table public.syndic_unit_charges
    enable row level security;


alter table public.syndic_payments
    enable row level security;


alter table public.syndic_payment_allocations
    enable row level security;



-- =========================================================
-- 8. APPELS DE FONDS — ADMIN
-- =========================================================

drop policy if exists
    "syndic_charge_calls_admin_select"
on public.syndic_charge_calls;


create policy
    "syndic_charge_calls_admin_select"

on public.syndic_charge_calls

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "syndic_charge_calls_admin_insert"
on public.syndic_charge_calls;


create policy
    "syndic_charge_calls_admin_insert"

on public.syndic_charge_calls

for insert

to authenticated

with check (

    (select public.is_admin())

    and

    status =
        'draft'

);


drop policy if exists
    "syndic_charge_calls_admin_update"
on public.syndic_charge_calls;


create policy
    "syndic_charge_calls_admin_update"

on public.syndic_charge_calls

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
    "syndic_charge_calls_admin_delete"
on public.syndic_charge_calls;


create policy
    "syndic_charge_calls_admin_delete"

on public.syndic_charge_calls

for delete

to authenticated

using (

    (select public.is_admin())

    and

    status =
        'draft'

);



-- =========================================================
-- 9. APPELS DE FONDS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "syndic_charge_calls_owner_select"
on public.syndic_charge_calls;


create policy
    "syndic_charge_calls_owner_select"

on public.syndic_charge_calls

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

        from public.syndic_unit_charges uc

        join public.owner_accounts oa
            on oa.id =
                uc.owner_account_id

        where
            uc.charge_call_id =
                syndic_charge_calls.id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 10. CRÉANCES — ADMIN
-- =========================================================

drop policy if exists
    "syndic_unit_charges_admin_select"
on public.syndic_unit_charges;


create policy
    "syndic_unit_charges_admin_select"

on public.syndic_unit_charges

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "syndic_unit_charges_admin_update"
on public.syndic_unit_charges;


create policy
    "syndic_unit_charges_admin_update"

on public.syndic_unit_charges

for update

to authenticated

using (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.syndic_charge_calls c

        where
            c.id =
                syndic_unit_charges.charge_call_id

            and
            c.status =
                'published'

    )

)

with check (

    (select public.is_admin())

    and

    exists (

        select 1

        from public.syndic_charge_calls c

        where
            c.id =
                syndic_unit_charges.charge_call_id

            and
            c.status =
                'published'

    )

);



-- =========================================================
-- 11. CRÉANCES — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "syndic_unit_charges_owner_select"
on public.syndic_unit_charges;


create policy
    "syndic_unit_charges_owner_select"

on public.syndic_unit_charges

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                syndic_unit_charges.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 12. PAIEMENTS — ADMIN
-- =========================================================

drop policy if exists
    "syndic_payments_admin_select"
on public.syndic_payments;


create policy
    "syndic_payments_admin_select"

on public.syndic_payments

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 13. PAIEMENTS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "syndic_payments_owner_select"
on public.syndic_payments;


create policy
    "syndic_payments_owner_select"

on public.syndic_payments

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                syndic_payments.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 14. VENTILATIONS — ADMIN
-- =========================================================

drop policy if exists
    "syndic_allocations_admin_select"
on public.syndic_payment_allocations;


create policy
    "syndic_allocations_admin_select"

on public.syndic_payment_allocations

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 15. VENTILATIONS — PROPRIÉTAIRE
-- =========================================================

drop policy if exists
    "syndic_allocations_owner_select"
on public.syndic_payment_allocations;


create policy
    "syndic_allocations_owner_select"

on public.syndic_payment_allocations

for select

to authenticated

using (

    exists (

        select 1

        from public.syndic_payments p

        join public.owner_accounts oa
            on oa.id =
                p.owner_account_id

        where
            p.id =
                syndic_payment_allocations.payment_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);



-- =========================================================
-- 16. RPC ADMIN : PUBLIER UN APPEL DE FONDS
--
-- Au moment de la publication :
--   - la liste des lots est figée ;
--   - une créance est créée par lot ;
--   - les comptes disabled sont exclus ;
--   - invited / active / suspended restent inclus car
--     la dette est rattachée au bien, pas à la capacité
--     de connexion au portail.
-- =========================================================

create or replace function public.admin_publish_syndic_charge_call(
    p_charge_call_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_call public.syndic_charge_calls%rowtype;

    v_unit_count integer;

    v_total_expected numeric(14,2);

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_call

    from public.syndic_charge_calls

    where id =
        p_charge_call_id

    for update;


    if not found then

        raise exception
            'Appel de fonds introuvable.';

    end if;


    if
        v_call.status <>
        'draft'
    then

        raise exception
            'Seul un brouillon peut être publié.';

    end if;


    if
        v_call.default_amount <= 0
    then

        raise exception
            'Le montant par défaut doit être supérieur à zéro.';

    end if;


    insert into public.syndic_unit_charges (

        charge_call_id,

        owner_account_unit_id,

        owner_account_id,

        building_code,

        apartment_number,

        base_amount,

        adjustment_amount

    )

    select

        v_call.id,

        u.id,

        u.owner_account_id,

        u.building_code,

        u.apartment_number,

        v_call.default_amount,

        0

    from public.owner_account_units u

    join public.owner_accounts oa
        on oa.id =
            u.owner_account_id

    where
        oa.status in (
            'invited',
            'active',
            'suspended'
        )

    on conflict (
        charge_call_id,
        owner_account_unit_id
    )
    do nothing;


    select
        count(*),
        coalesce(
            sum(amount_due),
            0
        )

    into
        v_unit_count,
        v_total_expected

    from public.syndic_unit_charges

    where charge_call_id =
        v_call.id;


    if
        v_unit_count = 0
    then

        raise exception
            'Aucun lot propriétaire n''est disponible pour cet appel de fonds.';

    end if;


    update public.syndic_charge_calls

    set
        status =
            'published',

        published_at =
            now(),

        closed_at =
            null,

        cancelled_at =
            null

    where id =
        v_call.id;


    return jsonb_build_object(

        'success',
        true,

        'chargeCallId',
        v_call.id,

        'status',
        'published',

        'unitCount',
        v_unit_count,

        'totalExpected',
        v_total_expected,

        'currency',
        v_call.currency

    );

end;
$$;



-- =========================================================
-- 17. RPC ADMIN : CLÔTURER UN APPEL DE FONDS
-- =========================================================

create or replace function public.admin_close_syndic_charge_call(
    p_charge_call_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_call public.syndic_charge_calls%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_call

    from public.syndic_charge_calls

    where id =
        p_charge_call_id

    for update;


    if not found then

        raise exception
            'Appel de fonds introuvable.';

    end if;


    if
        v_call.status <>
        'published'
    then

        raise exception
            'Seul un appel publié peut être clôturé.';

    end if;


    update public.syndic_charge_calls

    set
        status =
            'closed',

        closed_at =
            now()

    where id =
        p_charge_call_id;


    return jsonb_build_object(

        'success',
        true,

        'chargeCallId',
        p_charge_call_id,

        'status',
        'closed',

        'closedAt',
        now()

    );

end;
$$;



-- =========================================================
-- 18. RPC ADMIN : ANNULER UN APPEL PUBLIÉ
--
-- Un appel ayant reçu des paiements confirmés ne peut pas
-- être annulé tant que ces paiements ne sont pas extournés.
-- =========================================================

create or replace function public.admin_cancel_syndic_charge_call(
    p_charge_call_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_call public.syndic_charge_calls%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_call

    from public.syndic_charge_calls

    where id =
        p_charge_call_id

    for update;


    if not found then

        raise exception
            'Appel de fonds introuvable.';

    end if;


    if
        v_call.status <>
        'published'
    then

        raise exception
            'Seul un appel publié peut être annulé.';

    end if;


    if exists (

        select 1

        from public.syndic_unit_charges uc

        join public.syndic_payment_allocations a
            on a.unit_charge_id =
                uc.id

        join public.syndic_payments p
            on p.id =
                a.payment_id

        where
            uc.charge_call_id =
                p_charge_call_id

            and
            p.status =
                'confirmed'

    ) then

        raise exception
            'Cet appel possède des paiements confirmés. Extournez-les avant d''annuler l''appel.';

    end if;


    update public.syndic_charge_calls

    set
        status =
            'cancelled',

        cancelled_at =
            now()

    where id =
        p_charge_call_id;


    return jsonb_build_object(

        'success',
        true,

        'chargeCallId',
        p_charge_call_id,

        'status',
        'cancelled',

        'cancelledAt',
        now()

    );

end;
$$;



-- =========================================================
-- 19. RPC ADMIN : STATISTIQUES D'UN APPEL
-- =========================================================

create or replace function public.admin_get_syndic_charge_call_stats(
    p_charge_call_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_call public.syndic_charge_calls%rowtype;

    v_units integer;

    v_paid_units integer;

    v_partial_units integer;

    v_unpaid_units integer;

    v_total_expected numeric(14,2);

    v_total_paid numeric(14,2);

    v_outstanding numeric(14,2);

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_call

    from public.syndic_charge_calls

    where id =
        p_charge_call_id;


    if not found then

        raise exception
            'Appel de fonds introuvable.';

    end if;


    with charge_balances as (

        select

            uc.id,

            uc.amount_due,

            coalesce(
                sum(
                    case
                        when p.status = 'confirmed'
                        then a.amount
                        else 0
                    end
                ),
                0
            ) as amount_paid

        from public.syndic_unit_charges uc

        left join public.syndic_payment_allocations a
            on a.unit_charge_id =
                uc.id

        left join public.syndic_payments p
            on p.id =
                a.payment_id

        where
            uc.charge_call_id =
                p_charge_call_id

        group by
            uc.id,
            uc.amount_due

    )

    select

        count(*),

        count(*) filter (
            where amount_paid >= amount_due
        ),

        count(*) filter (
            where
                amount_paid > 0
                and
                amount_paid < amount_due
        ),

        count(*) filter (
            where amount_paid = 0
        ),

        coalesce(
            sum(amount_due),
            0
        ),

        coalesce(
            sum(
                least(
                    amount_paid,
                    amount_due
                )
            ),
            0
        ),

        coalesce(
            sum(
                greatest(
                    amount_due - amount_paid,
                    0
                )
            ),
            0
        )

    into
        v_units,
        v_paid_units,
        v_partial_units,
        v_unpaid_units,
        v_total_expected,
        v_total_paid,
        v_outstanding

    from charge_balances;


    return jsonb_build_object(

        'chargeCallId',
        p_charge_call_id,

        'status',
        v_call.status,

        'currency',
        v_call.currency,

        'units',
        v_units,

        'paidUnits',
        v_paid_units,

        'partialUnits',
        v_partial_units,

        'unpaidUnits',
        v_unpaid_units,

        'totalExpected',
        v_total_expected,

        'totalPaid',
        v_total_paid,

        'outstanding',
        v_outstanding

    );

end;
$$;



-- =========================================================
-- 20. RPC ADMIN : ENREGISTRER UN PAIEMENT
--
-- p_allocations :
--
-- [
--   {
--     "unitChargeId": "uuid",
--     "amount": 1200
--   }
-- ]
--
-- La somme des allocations doit être exactement égale
-- au montant du paiement afin d'éviter un solde non ventilé.
-- =========================================================

create or replace function public.admin_record_syndic_payment(
    p_owner_account_id uuid,
    p_payment_date date,
    p_amount numeric,
    p_payment_method text,
    p_reference text,
    p_notes text,
    p_allocations jsonb
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_payment_id uuid;

    v_item jsonb;

    v_unit_charge_id uuid;

    v_allocation_amount numeric(14,2);

    v_allocation_total numeric(14,2) :=
        0;

    v_charge public.syndic_unit_charges%rowtype;

    v_already_paid numeric(14,2);

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    if
        p_owner_account_id is null
        or
        not exists (

            select 1

            from public.owner_accounts

            where id =
                p_owner_account_id

        )
    then

        raise exception
            'Compte propriétaire introuvable.';

    end if;


    if
        p_payment_date is null
    then

        raise exception
            'Date de paiement obligatoire.';

    end if;


    if
        p_amount is null
        or
        p_amount <= 0
    then

        raise exception
            'Montant de paiement invalide.';

    end if;


    if
        p_payment_method not in (
            'bank_transfer',
            'cash',
            'cheque',
            'card',
            'other'
        )
    then

        raise exception
            'Mode de paiement invalide.';

    end if;


    if
        p_allocations is null
        or
        jsonb_typeof(
            p_allocations
        ) <> 'array'
        or
        jsonb_array_length(
            p_allocations
        ) = 0
    then

        raise exception
            'Au moins une ventilation est obligatoire.';

    end if;


    for v_item in

        select value

        from jsonb_array_elements(
            p_allocations
        )

    loop

        if
            not (
                v_item ? 'unitChargeId'
            )
            or
            not (
                v_item ? 'amount'
            )
        then

            raise exception
                'Ventilation invalide.';

        end if;


        begin

            v_unit_charge_id :=
                (
                    v_item ->> 'unitChargeId'
                )::uuid;

            v_allocation_amount :=
                (
                    v_item ->> 'amount'
                )::numeric;

        exception
            when others then

                raise exception
                    'Ventilation invalide.';

        end;


        if
            v_allocation_amount <= 0
        then

            raise exception
                'Le montant d''une ventilation doit être supérieur à zéro.';

        end if;


        select *
        into v_charge

        from public.syndic_unit_charges

        where id =
            v_unit_charge_id;


        if not found then

            raise exception
                'Créance introuvable.';

        end if;


        if
            v_charge.owner_account_id <>
            p_owner_account_id
        then

            raise exception
                'Une créance ne correspond pas au propriétaire sélectionné.';

        end if;


        select
            coalesce(
                sum(a.amount),
                0
            )

        into v_already_paid

        from public.syndic_payment_allocations a

        join public.syndic_payments p
            on p.id =
                a.payment_id

        where
            a.unit_charge_id =
                v_unit_charge_id

            and
            p.status =
                'confirmed';


        if
            v_already_paid +
            v_allocation_amount >
            v_charge.amount_due
        then

            raise exception
                'Une ventilation dépasse le montant restant dû.';

        end if;


        v_allocation_total :=
            v_allocation_total +
            v_allocation_amount;

    end loop;


    if
        abs(
            v_allocation_total -
            p_amount
        ) > 0.005
    then

        raise exception
            'La somme des ventilations doit être égale au montant du paiement.';

    end if;


    insert into public.syndic_payments (

        owner_account_id,

        payment_date,

        amount,

        currency,

        payment_method,

        reference,

        notes,

        status,

        recorded_by,

        confirmed_at

    )
    values (

        p_owner_account_id,

        p_payment_date,

        p_amount,

        'MAD',

        p_payment_method,

        nullif(
            trim(
                coalesce(
                    p_reference,
                    ''
                )
            ),
            ''
        ),

        nullif(
            trim(
                coalesce(
                    p_notes,
                    ''
                )
            ),
            ''
        ),

        'confirmed',

        auth.uid(),

        now()

    )
    returning id
    into v_payment_id;


    for v_item in

        select value

        from jsonb_array_elements(
            p_allocations
        )

    loop

        v_unit_charge_id :=
            (
                v_item ->> 'unitChargeId'
            )::uuid;

        v_allocation_amount :=
            (
                v_item ->> 'amount'
            )::numeric;


        insert into public.syndic_payment_allocations (

            payment_id,

            unit_charge_id,

            amount

        )
        values (

            v_payment_id,

            v_unit_charge_id,

            v_allocation_amount

        );

    end loop;


    return jsonb_build_object(

        'success',
        true,

        'paymentId',
        v_payment_id,

        'ownerAccountId',
        p_owner_account_id,

        'amount',
        p_amount,

        'currency',
        'MAD',

        'paymentDate',
        p_payment_date

    );

end;
$$;



-- =========================================================
-- 21. RPC ADMIN : EXTOURNER UN PAIEMENT
-- =========================================================

create or replace function public.admin_reverse_syndic_payment(
    p_payment_id uuid,
    p_reason text
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_payment public.syndic_payments%rowtype;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select *
    into v_payment

    from public.syndic_payments

    where id =
        p_payment_id

    for update;


    if not found then

        raise exception
            'Paiement introuvable.';

    end if;


    if
        v_payment.status <>
        'confirmed'
    then

        raise exception
            'Seul un paiement confirmé peut être extourné.';

    end if;


    if
        p_reason is null
        or
        length(
            trim(
                p_reason
            )
        ) < 3
    then

        raise exception
            'Un motif d''extourne est obligatoire.';

    end if;


    update public.syndic_payments

    set
        status =
            'reversed',

        reversed_at =
            now(),

        reversed_by =
            auth.uid(),

        reversal_reason =
            trim(
                p_reason
            )

    where id =
        p_payment_id;


    return jsonb_build_object(

        'success',
        true,

        'paymentId',
        p_payment_id,

        'status',
        'reversed',

        'reversedAt',
        now()

    );

end;
$$;



-- =========================================================
-- 22. RPC PROPRIÉTAIRE : SYNTHÈSE SYNDIC
--
-- Retourne uniquement les données du propriétaire connecté.
-- Aucun owner_account_id d'un autre propriétaire n'est exposé.
-- =========================================================

create or replace function public.owner_get_syndic_summary()
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_total_due numeric(14,2);

    v_total_paid numeric(14,2);

    v_outstanding numeric(14,2);

    v_charges jsonb;

    v_payments jsonb;

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


    with charge_balances as (

        select

            uc.id as
                unit_charge_id,

            c.id as
                charge_call_id,

            c.title,

            c.description,

            c.fiscal_year,

            c.period_label,

            c.charge_type,

            c.due_date,

            c.status as
                call_status,

            c.currency,

            uc.building_code,

            uc.apartment_number,

            uc.base_amount,

            uc.adjustment_amount,

            uc.amount_due,

            coalesce(
                sum(
                    case
                        when p.status = 'confirmed'
                        then a.amount
                        else 0
                    end
                ),
                0
            ) as amount_paid

        from public.syndic_unit_charges uc

        join public.syndic_charge_calls c
            on c.id =
                uc.charge_call_id

        left join public.syndic_payment_allocations a
            on a.unit_charge_id =
                uc.id

        left join public.syndic_payments p
            on p.id =
                a.payment_id

        where
            uc.owner_account_id =
                v_owner_account_id

            and
            c.status in (
                'published',
                'closed'
            )

        group by

            uc.id,

            c.id,

            c.title,

            c.description,

            c.fiscal_year,

            c.period_label,

            c.charge_type,

            c.due_date,

            c.status,

            c.currency,

            uc.building_code,

            uc.apartment_number,

            uc.base_amount,

            uc.adjustment_amount,

            uc.amount_due

    )

    select

        coalesce(
            sum(amount_due),
            0
        ),

        coalesce(
            sum(
                least(
                    amount_paid,
                    amount_due
                )
            ),
            0
        ),

        coalesce(
            sum(
                greatest(
                    amount_due -
                    amount_paid,
                    0
                )
            ),
            0
        ),

        coalesce(
            jsonb_agg(

                jsonb_build_object(

                    'unitChargeId',
                    unit_charge_id,

                    'chargeCallId',
                    charge_call_id,

                    'title',
                    title,

                    'description',
                    description,

                    'fiscalYear',
                    fiscal_year,

                    'periodLabel',
                    period_label,

                    'chargeType',
                    charge_type,

                    'dueDate',
                    due_date,

                    'callStatus',
                    call_status,

                    'currency',
                    currency,

                    'buildingCode',
                    building_code,

                    'apartmentNumber',
                    apartment_number,

                    'baseAmount',
                    base_amount,

                    'adjustmentAmount',
                    adjustment_amount,

                    'amountDue',
                    amount_due,

                    'amountPaid',
                    least(
                        amount_paid,
                        amount_due
                    ),

                    'outstanding',
                    greatest(
                        amount_due -
                        amount_paid,
                        0
                    ),

                    'paymentStatus',
                    case

                        when
                            amount_paid >=
                            amount_due
                        then
                            'paid'

                        when
                            amount_paid > 0
                        then
                            'partial'

                        else
                            'unpaid'

                    end

                )

                order by
                    due_date desc,
                    title

            ),
            '[]'::jsonb
        )

    into
        v_total_due,
        v_total_paid,
        v_outstanding,
        v_charges

    from charge_balances;


    select
        coalesce(
            jsonb_agg(

                jsonb_build_object(

                    'paymentId',
                    p.id,

                    'paymentDate',
                    p.payment_date,

                    'amount',
                    p.amount,

                    'currency',
                    p.currency,

                    'paymentMethod',
                    p.payment_method,

                    'reference',
                    p.reference,

                    'notes',
                    p.notes,

                    'status',
                    p.status,

                    'confirmedAt',
                    p.confirmed_at,

                    'reversedAt',
                    p.reversed_at,

                    'reversalReason',
                    p.reversal_reason

                )

                order by
                    p.payment_date desc,
                    p.created_at desc

            ),
            '[]'::jsonb
        )

    into v_payments

    from public.syndic_payments p

    where
        p.owner_account_id =
            v_owner_account_id

        and
        p.status in (
            'confirmed',
            'reversed'
        );


    return jsonb_build_object(

        'totalDue',
        v_total_due,

        'totalPaid',
        v_total_paid,

        'outstanding',
        v_outstanding,

        'currency',
        'MAD',

        'charges',
        v_charges,

        'payments',
        v_payments

    );

end;
$$;



-- =========================================================
-- 23. PRIVILÈGES TABLES
-- =========================================================

revoke all
on public.syndic_charge_calls
from anon;


revoke all
on public.syndic_unit_charges
from anon;


revoke all
on public.syndic_payments
from anon;


revoke all
on public.syndic_payment_allocations
from anon;



-- Appels de fonds :
-- CRUD de brouillon côté admin via RLS.
grant
    select,
    insert,
    delete
on public.syndic_charge_calls
to authenticated;


grant update (
    title,
    description,
    fiscal_year,
    period_label,
    charge_type,
    default_amount,
    currency,
    due_date
)
on public.syndic_charge_calls
to authenticated;



-- Créances :
-- lecture propriétaire / admin.
-- L'admin peut uniquement ajuster le montant,
-- pas réécrire le snapshot de propriété.
grant select
on public.syndic_unit_charges
to authenticated;


grant update (
    adjustment_amount,
    adjustment_note
)
on public.syndic_unit_charges
to authenticated;



-- Paiements et allocations :
-- lecture seulement depuis le navigateur.
-- Toute écriture passe par les RPC SECURITY DEFINER.
grant select
on public.syndic_payments
to authenticated;


grant select
on public.syndic_payment_allocations
to authenticated;



grant all
on public.syndic_charge_calls
to service_role;


grant all
on public.syndic_unit_charges
to service_role;


grant all
on public.syndic_payments
to service_role;


grant all
on public.syndic_payment_allocations
to service_role;



-- =========================================================
-- 24. PRIVILÈGES FUNCTIONS
-- =========================================================

revoke all
on function public.admin_publish_syndic_charge_call(uuid)
from public;


revoke all
on function public.admin_publish_syndic_charge_call(uuid)
from anon;


grant execute
on function public.admin_publish_syndic_charge_call(uuid)
to authenticated;


grant execute
on function public.admin_publish_syndic_charge_call(uuid)
to service_role;



revoke all
on function public.admin_close_syndic_charge_call(uuid)
from public;


revoke all
on function public.admin_close_syndic_charge_call(uuid)
from anon;


grant execute
on function public.admin_close_syndic_charge_call(uuid)
to authenticated;


grant execute
on function public.admin_close_syndic_charge_call(uuid)
to service_role;



revoke all
on function public.admin_cancel_syndic_charge_call(uuid)
from public;


revoke all
on function public.admin_cancel_syndic_charge_call(uuid)
from anon;


grant execute
on function public.admin_cancel_syndic_charge_call(uuid)
to authenticated;


grant execute
on function public.admin_cancel_syndic_charge_call(uuid)
to service_role;



revoke all
on function public.admin_get_syndic_charge_call_stats(uuid)
from public;


revoke all
on function public.admin_get_syndic_charge_call_stats(uuid)
from anon;


grant execute
on function public.admin_get_syndic_charge_call_stats(uuid)
to authenticated;


grant execute
on function public.admin_get_syndic_charge_call_stats(uuid)
to service_role;



revoke all
on function public.admin_record_syndic_payment(
    uuid,
    date,
    numeric,
    text,
    text,
    text,
    jsonb
)
from public;


revoke all
on function public.admin_record_syndic_payment(
    uuid,
    date,
    numeric,
    text,
    text,
    text,
    jsonb
)
from anon;


grant execute
on function public.admin_record_syndic_payment(
    uuid,
    date,
    numeric,
    text,
    text,
    text,
    jsonb
)
to authenticated;


grant execute
on function public.admin_record_syndic_payment(
    uuid,
    date,
    numeric,
    text,
    text,
    text,
    jsonb
)
to service_role;



revoke all
on function public.admin_reverse_syndic_payment(
    uuid,
    text
)
from public;


revoke all
on function public.admin_reverse_syndic_payment(
    uuid,
    text
)
from anon;


grant execute
on function public.admin_reverse_syndic_payment(
    uuid,
    text
)
to authenticated;


grant execute
on function public.admin_reverse_syndic_payment(
    uuid,
    text
)
to service_role;



revoke all
on function public.owner_get_syndic_summary()
from public;


revoke all
on function public.owner_get_syndic_summary()
from anon;


grant execute
on function public.owner_get_syndic_summary()
to authenticated;


grant execute
on function public.owner_get_syndic_summary()
to service_role;
