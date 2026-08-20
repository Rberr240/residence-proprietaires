-- =========================================================
-- MIRADOR GOLF 1
-- HARDEN SYNDIC PAYMENT ALLOCATION — ROW LOCKING
--
-- Constat (audit sécurité 2026-08-19) :
--   validate_syndic_payment_allocation() et
--   admin_record_syndic_payment() lisent syndic_unit_charges
--   (et, pour le trigger, syndic_payments) sans verrou de ligne
--   avant de comparer la somme des ventilations confirmées au
--   montant dû. Deux insertions concurrentes de ventilations
--   ciblant la même créance peuvent chacune lire un total encore
--   à jour avant l'autre, passer la vérification, et sur-allouer
--   la créance (aucune contrainte unique ne peut protéger une
--   somme). Cette migration ferme la fenêtre de course en
--   verrouillant explicitement (`for update`) les lignes lues
--   avant le calcul du total, sans changer le comportement
--   observable en l'absence de concurrence.
--
-- Remplace uniquement le corps des deux fonctions existantes
-- (create or replace function, signatures identiques) — aucune
-- migration déjà appliquée n'est modifiée.
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
        new.payment_id

    for update;


    if not found then

        raise exception
            'Paiement introuvable.';

    end if;


    select *
    into v_charge

    from public.syndic_unit_charges

    where id =
        new.unit_charge_id

    for update;


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

    v_lock_charge_id uuid;

    v_lock_charge_ids uuid[] :=
        '{}';

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


    -- -----------------------------------------------------
    -- Verrouille toutes les créances référencées par cette
    -- demande, dans un ordre déterministe (id croissant),
    -- avant toute validation par montant.
    --
    -- Sans cet ordre canonique, deux paiements concurrents
    -- ciblant les deux mêmes créances mais énumérées dans un
    -- ordre différent pourraient chacun verrouiller une
    -- créance puis attendre l'autre indéfiniment (interblocage
    -- classique) — Postgres finirait par annuler l'une des deux
    -- transactions plutôt que de corrompre les données, mais un
    -- ordre déterministe évite cet échec évitable.
    --
    -- La validation de forme (clé "unitChargeId" présente et
    -- castable en uuid) est répliquée ici à l'identique de celle
    -- de la boucle existante plus bas, pour lever la même erreur
    -- ("Ventilation invalide.") avant toute tentative de verrou.
    -- -----------------------------------------------------

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
        then

            raise exception
                'Ventilation invalide.';

        end if;


        begin

            v_lock_charge_id :=
                (
                    v_item ->> 'unitChargeId'
                )::uuid;

        exception
            when others then

                raise exception
                    'Ventilation invalide.';

        end;


        if
            not (
                v_lock_charge_id =
                    any(v_lock_charge_ids)
            )
        then

            v_lock_charge_ids :=
                array_append(
                    v_lock_charge_ids,
                    v_lock_charge_id
                );

        end if;

    end loop;


    for v_lock_charge_id in

        select
            unnest(v_lock_charge_ids)

        order by
            1

    loop

        perform 1

        from public.syndic_unit_charges

        where id =
            v_lock_charge_id

        for update;

    end loop;


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
            v_unit_charge_id

        for update;


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
