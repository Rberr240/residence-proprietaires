-- =========================================================
-- MIRADOR GOLF 1
-- SYNDIC V2 — Hardening paiements / créances
--
-- Empêche toute nouvelle ventilation de paiement sur
-- un appel de fonds en brouillon ou annulé.
--
-- Les paiements restent autorisés pour :
--   - published
--   - closed
--
-- Ceci permet notamment d'enregistrer un paiement tardif
-- après la clôture administrative d'un appel.
-- =========================================================


create or replace function public.validate_syndic_allocation_call_status()
returns trigger
language plpgsql
set search_path = ''
as $$
declare

    v_call_status text;

begin

    select c.status
    into v_call_status

    from public.syndic_unit_charges uc

    join public.syndic_charge_calls c
        on c.id =
            uc.charge_call_id

    where uc.id =
        new.unit_charge_id;


    if v_call_status is null then

        raise exception
            'Appel de fonds introuvable pour cette créance.';

    end if;


    if v_call_status not in (
        'published',
        'closed'
    ) then

        raise exception
            'Un paiement ne peut être affecté qu''à un appel publié ou clôturé.';

    end if;


    return new;

end;
$$;


drop trigger if exists
    syndic_payment_allocations_validate_call_status
on public.syndic_payment_allocations;


create trigger
    syndic_payment_allocations_validate_call_status

before insert or update
on public.syndic_payment_allocations

for each row

execute function
    public.validate_syndic_allocation_call_status();
