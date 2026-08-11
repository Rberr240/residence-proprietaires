-- =========================================================
-- MIRADOR GOLF 1
-- Atomic owner validation
-- =========================================================

create or replace function public.admin_validate_owner_submission(
    p_submission_id uuid,
    p_code_hash text,
    p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_submission public.owner_submissions%rowtype;
    v_owner_account_id uuid;
    v_unit_id uuid;
    v_already_validated boolean := false;
begin

    -- -----------------------------------------------------
    -- ADMIN ONLY
    -- -----------------------------------------------------

    if not public.is_admin() then
        raise exception 'Accès administrateur requis.'
            using errcode = '42501';
    end if;


    -- -----------------------------------------------------
    -- INPUT VALIDATION
    -- -----------------------------------------------------

    if p_submission_id is null then
        raise exception 'Identifiant de soumission manquant.';
    end if;

    if p_code_hash is null
       or p_code_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'Empreinte du code invalide.';
    end if;

    if p_expires_at is null
       or p_expires_at <= now() then
        raise exception 'Date d''expiration invalide.';
    end if;


    -- -----------------------------------------------------
    -- LOCK SUBMISSION
    -- -----------------------------------------------------

    select *
    into v_submission
    from public.owner_submissions
    where id = p_submission_id
    for update;

    if not found then
        raise exception 'Propriétaire introuvable.';
    end if;

    if v_submission.status = 'rejected' then
        raise exception 'Cette inscription a été rejetée.';
    end if;


    -- -----------------------------------------------------
    -- ALREADY LINKED ?
    -- -----------------------------------------------------

    select owner_account_id
    into v_owner_account_id
    from public.owner_account_units
    where submission_id = p_submission_id;

    if v_owner_account_id is not null then

        v_already_validated := true;

    else

        -- -------------------------------------------------
        -- CREATE OWNER ACCOUNT
        -- -------------------------------------------------

        insert into public.owner_accounts (
            first_name,
            last_name,
            phone,
            whatsapp,
            email,
            status
        )
        values (
            trim(v_submission.first_name),
            trim(v_submission.last_name),
            trim(v_submission.phone),
            nullif(trim(v_submission.whatsapp), ''),
            nullif(lower(trim(v_submission.email)), ''),
            'invited'
        )
        returning id
        into v_owner_account_id;


        -- -------------------------------------------------
        -- LINK APARTMENT
        -- -------------------------------------------------

        insert into public.owner_account_units (
            owner_account_id,
            submission_id,
            building_code,
            apartment_number,
            is_primary
        )
        values (
            v_owner_account_id,
            p_submission_id,
            v_submission.building_code,
            v_submission.apartment_number,
            true
        )
        returning id
        into v_unit_id;

    end if;


    -- -----------------------------------------------------
    -- REVOKE PREVIOUS UNUSED CODE
    -- -----------------------------------------------------

    update public.owner_activation_codes
    set revoked_at = now()
    where owner_account_id = v_owner_account_id
      and used_at is null
      and revoked_at is null;


    -- -----------------------------------------------------
    -- CREATE NEW ACTIVATION CODE HASH
    -- -----------------------------------------------------

    insert into public.owner_activation_codes (
        owner_account_id,
        code_hash,
        expires_at
    )
    values (
        v_owner_account_id,
        p_code_hash,
        p_expires_at
    );


    -- -----------------------------------------------------
    -- VALIDATE SUBMISSION
    -- -----------------------------------------------------

    update public.owner_submissions
    set status = 'verified'
    where id = p_submission_id;


    -- -----------------------------------------------------
    -- RESULT
    -- -----------------------------------------------------

    return jsonb_build_object(
        'success', true,
        'ownerAccountId', v_owner_account_id,
        'submissionId', p_submission_id,
        'alreadyValidated', v_already_validated,
        'expiresAt', p_expires_at
    );

end;
$$;


revoke all
on function public.admin_validate_owner_submission(
    uuid,
    text,
    timestamptz
)
from public, anon;


grant execute
on function public.admin_validate_owner_submission(
    uuid,
    text,
    timestamptz
)
to authenticated;