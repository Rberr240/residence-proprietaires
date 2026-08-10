-- =========================================================
-- MIRADOR GOLF
-- Save meeting preferences during owner registration
-- =========================================================

-- Create the current draft meeting if none exists yet.
insert into public.meetings (
    title,
    status
)
select
    'Prochaine réunion des propriétaires',
    'draft'
where not exists (
    select 1
    from public.meetings
    where status in ('draft', 'scheduled')
);


-- Extended atomic registration function.
create or replace function public.register_owner_with_session(
    p_token_hash text,
    p_first_name text,
    p_last_name text,
    p_phone text,
    p_whatsapp text,
    p_email text,
    p_consent boolean,
    p_attendance text,
    p_availability text[],
    p_subject text
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
    v_meeting_id uuid;

    v_now timestamptz := now();
begin

    -- -----------------------------------------------------
    -- Basic validation
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

    if p_attendance is not null
       and p_attendance not in ('yes', 'no', 'maybe')
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_attendance'
        );
    end if;

    if p_availability is null then
        p_availability := '{}'::text[];
    end if;

    if not (
        p_availability
        <@ array['morning', 'afternoon', 'evening']::text[]
    )
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_availability'
        );
    end if;

    if p_subject is not null
       and length(trim(p_subject)) > 1000
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'invalid_subject'
        );
    end if;


    -- -----------------------------------------------------
    -- Lock and validate registration session
    -- -----------------------------------------------------

    select rs.*
    into v_session
    from public.registration_sessions rs
    where rs.token_hash = p_token_hash
    for update;

    if not found
       or v_session.consumed_at is not null
       or v_session.expires_at <= v_now
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'session_unavailable'
        );
    end if;


    -- -----------------------------------------------------
    -- Lock and validate access code
    -- -----------------------------------------------------

    select ac.*
    into v_access_code
    from public.access_codes ac
    where ac.id = v_session.access_code_id
    for update;

    if not found
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'access_unavailable'
        );
    end if;

    if v_access_code.apartment_id <> v_session.apartment_id
    then
        raise exception
            'Registration session apartment mismatch';
    end if;

    if v_access_code.active is not true
       or v_access_code.used_at is not null
       or (
            v_access_code.expires_at is not null
            and v_access_code.expires_at <= v_now
       )
    then
        return jsonb_build_object(
            'success', false,
            'reason', 'access_unavailable'
        );
    end if;


    -- -----------------------------------------------------
    -- Find current meeting
    -- -----------------------------------------------------

    select m.id
    into v_meeting_id
    from public.meetings m
    where m.status in ('scheduled', 'draft')
    order by
        case when m.status = 'scheduled' then 0 else 1 end,
        m.meeting_date nulls last,
        m.created_at desc
    limit 1;

    if v_meeting_id is null
    then
        raise exception 'No active meeting found';
    end if;


    -- -----------------------------------------------------
    -- Create owner
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
    -- Save meeting preferences
    -- -----------------------------------------------------

    insert into public.meeting_responses (
        meeting_id,
        owner_id,
        attendance,
        availability,
        subject
    )
    values (
        v_meeting_id,
        v_owner_id,
        p_attendance,
        p_availability,
        nullif(trim(p_subject), '')
    );


    -- -----------------------------------------------------
    -- Consume session and access code
    -- -----------------------------------------------------

    update public.registration_sessions
    set consumed_at = v_now
    where id = v_session.id;

    update public.access_codes
    set used_at = v_now
    where id = v_access_code.id;


    return jsonb_build_object(
        'success', true,
        'owner_id', v_owner_id,
        'apartment_id', v_session.apartment_id,
        'meeting_id', v_meeting_id
    );

end;
$$;


-- Browser roles must never call this RPC directly.

revoke execute
on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean,
    text,
    text[],
    text
)
from public, anon, authenticated;


grant execute
on function public.register_owner_with_session(
    text,
    text,
    text,
    text,
    text,
    text,
    boolean,
    text,
    text[],
    text
)
to service_role;