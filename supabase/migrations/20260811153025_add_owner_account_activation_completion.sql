-- =========================================================
-- MIRADOR GOLF 1
-- Finalisation atomique de l'activation propriétaire
-- =========================================================


create or replace function public.complete_owner_activation(
    p_owner_account_id uuid,
    p_activation_code_id uuid,
    p_auth_user_id uuid,
    p_phone_e164 text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare

    v_owner public.owner_accounts%rowtype;

    v_code public.owner_activation_codes%rowtype;

begin

    -- =====================================================
    -- VALIDATION PARAMÈTRES
    -- =====================================================

    if p_owner_account_id is null then
        raise exception 'Compte propriétaire manquant.';
    end if;


    if p_activation_code_id is null then
        raise exception 'Code d''activation manquant.';
    end if;


    if p_auth_user_id is null then
        raise exception 'Utilisateur Auth manquant.';
    end if;


    if p_phone_e164 is null
       or length(trim(p_phone_e164)) < 8
       or length(trim(p_phone_e164)) > 20 then

        raise exception 'Numéro de téléphone invalide.';

    end if;



    -- =====================================================
    -- VERROUILLAGE DU COMPTE
    -- =====================================================

    select *
    into v_owner

    from public.owner_accounts

    where id = p_owner_account_id

    for update;


    if not found then

        raise exception 'Compte propriétaire introuvable.';

    end if;



    -- =====================================================
    -- VERROUILLAGE DU CODE
    -- =====================================================

    select *
    into v_code

    from public.owner_activation_codes

    where id = p_activation_code_id

    for update;


    if not found then

        raise exception 'Code d''activation introuvable.';

    end if;



    -- =====================================================
    -- LE CODE DOIT APPARTENIR AU COMPTE
    -- =====================================================

    if v_code.owner_account_id <> v_owner.id then

        raise exception 'Code d''activation invalide.';

    end if;



    -- =====================================================
    -- CODE RÉVOQUÉ ?
    -- =====================================================

    if v_code.revoked_at is not null then

        raise exception 'Ce code d''activation a été révoqué.';

    end if;



    -- =====================================================
    -- CODE DÉJÀ UTILISÉ ?
    -- =====================================================

    if v_code.used_at is not null then

        raise exception 'Ce code d''activation a déjà été utilisé.';

    end if;



    -- =====================================================
    -- CODE EXPIRÉ ?
    -- =====================================================

    if v_code.expires_at <= now() then

        raise exception 'Ce code d''activation a expiré.';

    end if;



    -- =====================================================
    -- COMPTE DÉJÀ ACTIF ?
    -- =====================================================

    if v_owner.status = 'active' then

        if v_owner.auth_user_id = p_auth_user_id then

            return jsonb_build_object(

                'success',
                true,

                'alreadyActive',
                true,

                'ownerAccountId',
                v_owner.id,

                'authUserId',
                p_auth_user_id

            );

        end if;


        raise exception 'Ce compte propriétaire est déjà actif.';

    end if;



    -- =====================================================
    -- COMPTE DÉJÀ LIÉ À UN AUTRE USER AUTH ?
    -- =====================================================

    if v_owner.auth_user_id is not null
       and v_owner.auth_user_id <> p_auth_user_id then

        raise exception
            'Ce compte est déjà lié à un autre utilisateur.';

    end if;



    -- =====================================================
    -- ACTIVER LE COMPTE
    -- =====================================================

    update public.owner_accounts

    set

        auth_user_id =
            p_auth_user_id,

        phone_e164 =
            trim(p_phone_e164),

        status =
            'active',

        activated_at =
            now()

    where id =
        p_owner_account_id;



    -- =====================================================
    -- CONSOMMER LE CODE
    -- =====================================================

    update public.owner_activation_codes

    set used_at =
        now()

    where id =
        p_activation_code_id;



    -- =====================================================
    -- RÉSULTAT
    -- =====================================================

    return jsonb_build_object(

        'success',
        true,

        'alreadyActive',
        false,

        'ownerAccountId',
        p_owner_account_id,

        'authUserId',
        p_auth_user_id,

        'phone',
        trim(p_phone_e164)

    );

end;
$$;



-- =========================================================
-- SÉCURITÉ
--
-- Cette fonction ne doit JAMAIS être appelée directement
-- par le navigateur.
-- =========================================================

revoke all
on function public.complete_owner_activation(
    uuid,
    uuid,
    uuid,
    text
)
from public;


revoke all
on function public.complete_owner_activation(
    uuid,
    uuid,
    uuid,
    text
)
from anon;


revoke all
on function public.complete_owner_activation(
    uuid,
    uuid,
    uuid,
    text
)
from authenticated;


grant execute
on function public.complete_owner_activation(
    uuid,
    uuid,
    uuid,
    text
)
to service_role;