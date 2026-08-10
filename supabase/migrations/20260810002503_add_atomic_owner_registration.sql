-- =========================================================
-- MIRADOR GOLF
-- Atomic owner registration
-- =========================================================
--
-- This function finalizes an owner registration atomically:
--
--   1. Lock registration session
--   2. Validate session
--   3. Lock access code
--   4. Validate access code
--   5. Create owner
--   6. Consume registration session
--   7. Mark access code as used
--
-- All database changes happen inside the same PostgreSQL
-- transaction.
--
-- The browser NEVER calls this function directly.
-- Only the trusted Edge Function may call it.
-- =========================================================


create or replace function public.register_owner_with_session(
    p_token_hash text,
    p_first_name text,
    p_last_name text,
    p_phone text,
    p_whatsapp text default null,
    p_email text default null,
    p_consent boolean default false
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
    v_session public.registration_sessions%rowtype;
    v_access_code public.access_codes%rowtype;

    v_owner_id uuid;

    v_now timestamptz := now();
begin

    -- -----------------------------------------------------
    -- 1. BASIC INPUT VALIDATION
    -- -----------------------------------------------------

    if p_token_hash is null
       or p_token_hash !~ '^[0-9a-f]{64}$'
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_session'
        );
    end if;


    if p_first_name is null
       or length(trim(p_first_name)) < 1
       or length(trim(p_first_name)) > 100
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_first_name'
        );
    end if;


    if p_last_name is null
       or length(trim(p_last_name)) < 1
       or length(trim(p_last_name)) > 100
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_last_name'
        );
    end if;


    if p_phone is null
       or length(trim(p_phone)) < 5
       or length(trim(p_phone)) > 30
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_phone'
        );
    end if;


    if p_whatsapp is not null
       and length(trim(p_whatsapp)) > 30
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_whatsapp'
        );
    end if;


    if p_email is not null
       and length(trim(p_email)) > 254
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_email'
        );
    end if;


    if p_consent is not true
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'consent_required'
        );
    end if;


    -- -----------------------------------------------------
    -- 2. LOCK REGISTRATION SESSION
    --
    -- FOR UPDATE is important:
    -- two simultaneous submissions using the same token
    -- cannot both consume the same session.
    -- -----------------------------------------------------

    select rs.*
    into v_session
    from public.registration_sessions as rs
    where rs.token_hash = p_token_hash
    for update;


    if not found
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_session'
        );
    end if;


    if v_session.consumed_at is not null
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'session_unavailable'
        );
    end if;


    if v_session.expires_at <= v_now
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'session_unavailable'
        );
    end if;


    -- -----------------------------------------------------
    -- 3. LOCK ACCESS CODE
    --
    -- A second registration session for the same access
    -- code will also be unable to create another owner
    -- after the first registration succeeds.
    -- -----------------------------------------------------

    select ac.*
    into v_access_code
    from public.access_codes as ac
    where ac.id = v_session.access_code_id
    for update;


    if not found
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'access_unavailable'
        );
    end if;


    -- Defensive consistency check.
    if v_access_code.apartment_id <> v_session.apartment_id
    then
        raise exception
            'Registration session apartment mismatch';
    end if;


    if v_access_code.active is not true
       or v_access_code.used_at is not null
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'access_unavailable'
        );
    end if;


    if v_access_code.expires_at is not null
       and v_access_code.expires_at <= v_now
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'access_unavailable'
        );
    end if;


    -- -----------------------------------------------------
    -- 4. CREATE OWNER
    -- -----------------------------------------------------

    insert into public.owners (
        apartment_id,
        first_name,
        last_name,
        phone,
        whatsapp,
        email,
        verified,
        consent,
        consent_at
    )
    values (
        v_session.apartment_id,
        trim(p_first_name),
        trim(p_last_name),
        trim(p_phone),
        nullif(trim(p_whatsapp), ''),
        nullif(lower(trim(p_email)), ''),
        true,
        true,
        v_now
    )
    returning id
    into v_owner_id;


    -- -----------------------------------------------------
    -- 5. CONSUME REGISTRATION SESSION
    -- -----------------------------------------------------

    update public.registration_sessions
    set consumed_at = v_now
    where id = v_session.id;


    -- -----------------------------------------------------
    -- 6. MARK ACCESS CODE AS USED
    -- -----------------------------------------------------

    update public.access_codes
    set used_at = v_now
    where id = v_access_code.id;


    -- -----------------------------------------------------
    -- 7. SUCCESS
    -- -----------------------------------------------------

    return jsonb_build_object(
        'success', true,
        'owner_id', v_owner_id,
        'apartment_id', v_session.apartment_id
    );

end;
$$;


-- =========================================================
-- PRIVILEGES
-- =========================================================
--
-- Never expose this RPC directly to browser roles.
-- =========================================================

revoke execute
on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean
)
from public;


revoke execute
on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean
)
from anon, authenticated;


grant execute
on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean
)
to service_role;


comment on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean
)
is
'Atomically creates a Mirador Golf owner from a valid temporary registration session.';