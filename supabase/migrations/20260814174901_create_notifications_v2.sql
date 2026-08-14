-- =========================================================
-- MIRADOR GOLF 1
-- NOTIFICATIONS V2 — MULTI-CANAL
--
-- Objectifs :
--   1. Inbox interne propriétaire (source de vérité)
--   2. Préférences par propriétaire
--   3. Outbox durable multi-canal :
--        - Email      -> Resend
--        - WhatsApp   -> Twilio WhatsApp
--        - Push Web   -> OneSignal
--   4. Idempotence / anti-doublon
--   5. Retries et journal d'envoi
--   6. Webhooks provider-ready
--   7. Génération automatique lors de :
--        - publication réunion
--        - publication vote
--        - publication appel de fonds
--        - publication annonce
--        - publication document
--        - paiement syndic confirmé / extourné
--
-- IMPORTANT :
--   - Aucun secret provider n'est stocké dans PostgreSQL.
--   - Les clés Resend / Twilio / OneSignal resteront dans
--     Supabase Edge Function Secrets.
--   - WhatsApp / Email / Push sont désactivés par défaut.
--   - L'in-app reste disponible pour tout compte actif.
-- =========================================================


-- =========================================================
-- 1. PRÉFÉRENCES DE NOTIFICATION
-- =========================================================

create table if not exists public.owner_notification_preferences (

    owner_account_id uuid primary key
        references public.owner_accounts(id)
        on delete cascade,

    in_app_enabled boolean not null
        default true,

    email_enabled boolean not null
        default false,

    whatsapp_enabled boolean not null
        default false,

    push_enabled boolean not null
        default false,

    email_opted_in_at timestamptz null,

    email_opted_out_at timestamptz null,

    whatsapp_opted_in_at timestamptz null,

    whatsapp_opted_out_at timestamptz null,

    push_opted_in_at timestamptz null,

    push_opted_out_at timestamptz null,

    quiet_hours_start time null,

    quiet_hours_end time null,

    timezone text not null
        default 'Africa/Casablanca',

    digest_mode text not null
        default 'immediate',

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint owner_notification_preferences_digest_check
        check (
            digest_mode in (
                'immediate',
                'daily'
            )
        ),

    constraint owner_notification_preferences_timezone_not_blank
        check (
            length(trim(timezone)) > 0
        )
);


create index if not exists
    owner_notification_preferences_email_idx
on public.owner_notification_preferences(email_enabled);


create index if not exists
    owner_notification_preferences_whatsapp_idx
on public.owner_notification_preferences(whatsapp_enabled);


create index if not exists
    owner_notification_preferences_push_idx
on public.owner_notification_preferences(push_enabled);



-- =========================================================
-- 2. ÉVÉNEMENTS DE NOTIFICATION
--
-- Une ligne = un événement métier global.
-- event_key assure l'idempotence.
-- =========================================================

create table if not exists public.notification_events (

    id uuid primary key
        default gen_random_uuid(),

    event_key text not null
        unique,

    event_type text not null,

    category text not null,

    source_type text not null,

    source_id uuid not null,

    title text not null,

    body text not null,

    priority text not null
        default 'normal',

    action_section text null,

    action_entity_id uuid null,

    metadata jsonb not null
        default '{}'::jsonb,

    occurred_at timestamptz not null
        default now(),

    created_at timestamptz not null
        default now(),

    constraint notification_events_event_key_not_blank
        check (
            length(trim(event_key)) > 0
        ),

    constraint notification_events_event_type_not_blank
        check (
            length(trim(event_type)) > 0
        ),

    constraint notification_events_category_check
        check (
            category in (
                'meeting',
                'vote',
                'syndic',
                'announcement',
                'document',
                'account',
                'system'
            )
        ),

    constraint notification_events_priority_check
        check (
            priority in (
                'normal',
                'high',
                'urgent'
            )
        ),

    constraint notification_events_title_not_blank
        check (
            length(trim(title)) > 0
        ),

    constraint notification_events_body_not_blank
        check (
            length(trim(body)) > 0
        )
);


create index if not exists
    notification_events_category_idx
on public.notification_events(category);


create index if not exists
    notification_events_source_idx
on public.notification_events(source_type, source_id);


create index if not exists
    notification_events_occurred_at_idx
on public.notification_events(occurred_at desc);



-- =========================================================
-- 3. INBOX PROPRIÉTAIRE
--
-- Une ligne = un événement destiné à un propriétaire.
-- =========================================================

create table if not exists public.owner_notifications (

    id uuid primary key
        default gen_random_uuid(),

    event_id uuid not null
        references public.notification_events(id)
        on delete cascade,

    owner_account_id uuid not null
        references public.owner_accounts(id)
        on delete cascade,

    seen_at timestamptz null,

    opened_at timestamptz null,

    read_at timestamptz null,

    dismissed_at timestamptz null,

    created_at timestamptz not null
        default now(),

    constraint owner_notifications_unique
        unique (
            event_id,
            owner_account_id
        )
);


create index if not exists
    owner_notifications_owner_created_idx
on public.owner_notifications(
    owner_account_id,
    created_at desc
);


create index if not exists
    owner_notifications_owner_unread_idx
on public.owner_notifications(
    owner_account_id,
    read_at
);



-- =========================================================
-- 4. OUTBOX MULTI-CANAL
--
-- Une ligne = une tentative logique de livraison
-- pour un canal externe.
-- =========================================================

create table if not exists public.notification_deliveries (

    id uuid primary key
        default gen_random_uuid(),

    owner_notification_id uuid not null
        references public.owner_notifications(id)
        on delete cascade,

    channel text not null,

    provider text not null,

    destination text not null,

    status text not null
        default 'pending',

    scheduled_for timestamptz not null
        default now(),

    next_attempt_at timestamptz not null
        default now(),

    attempt_count integer not null
        default 0,

    max_attempts integer not null
        default 5,

    processing_started_at timestamptz null,

    sent_at timestamptz null,

    delivered_at timestamptz null,

    failed_at timestamptz null,

    skipped_at timestamptz null,

    provider_message_id text null,

    last_error text null,

    metadata jsonb not null
        default '{}'::jsonb,

    created_at timestamptz not null
        default now(),

    updated_at timestamptz not null
        default now(),

    constraint notification_deliveries_channel_check
        check (
            channel in (
                'email',
                'whatsapp',
                'push'
            )
        ),

    constraint notification_deliveries_status_check
        check (
            status in (
                'pending',
                'processing',
                'sent',
                'delivered',
                'failed',
                'skipped',
                'cancelled'
            )
        ),

    constraint notification_deliveries_attempt_count_check
        check (
            attempt_count >= 0
        ),

    constraint notification_deliveries_max_attempts_check
        check (
            max_attempts between 1 and 20
        ),

    constraint notification_deliveries_destination_not_blank
        check (
            length(trim(destination)) > 0
        ),

    constraint notification_deliveries_unique_channel
        unique (
            owner_notification_id,
            channel
        )
);


create index if not exists
    notification_deliveries_pending_idx
on public.notification_deliveries(
    status,
    next_attempt_at,
    scheduled_for
);


create index if not exists
    notification_deliveries_provider_message_idx
on public.notification_deliveries(
    provider,
    provider_message_id
)
where provider_message_id is not null;



-- =========================================================
-- 5. HISTORIQUE DE CHAQUE TENTATIVE PROVIDER
-- =========================================================

create table if not exists public.notification_delivery_attempts (

    id uuid primary key
        default gen_random_uuid(),

    delivery_id uuid not null
        references public.notification_deliveries(id)
        on delete cascade,

    attempt_number integer not null,

    provider text not null,

    status text not null,

    http_status integer null,

    provider_message_id text null,

    error_code text null,

    error_message text null,

    response_metadata jsonb not null
        default '{}'::jsonb,

    started_at timestamptz not null
        default now(),

    completed_at timestamptz null,

    created_at timestamptz not null
        default now(),

    constraint notification_delivery_attempts_number_check
        check (
            attempt_number >= 1
        ),

    constraint notification_delivery_attempts_status_check
        check (
            status in (
                'processing',
                'sent',
                'delivered',
                'failed',
                'skipped'
            )
        )
);


create index if not exists
    notification_delivery_attempts_delivery_idx
on public.notification_delivery_attempts(
    delivery_id,
    attempt_number
);



-- =========================================================
-- 6. WEBHOOKS PROVIDERS
--
-- Stocke les callbacks de livraison/clic/échec.
-- Ne doit jamais contenir de secret provider.
-- =========================================================

create table if not exists public.notification_provider_events (

    id uuid primary key
        default gen_random_uuid(),

    provider text not null,

    provider_event_id text null,

    provider_message_id text null,

    event_type text not null,

    payload jsonb not null
        default '{}'::jsonb,

    received_at timestamptz not null
        default now(),

    processed_at timestamptz null,

    created_at timestamptz not null
        default now()
);


create unique index if not exists
    notification_provider_events_unique_idx
on public.notification_provider_events(
    provider,
    provider_event_id
)
where provider_event_id is not null;


create index if not exists
    notification_provider_events_message_idx
on public.notification_provider_events(
    provider,
    provider_message_id
)
where provider_message_id is not null;



-- =========================================================
-- 7. UPDATED_AT
-- =========================================================

create or replace function public.set_notification_updated_at()
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
    owner_notification_preferences_set_updated_at
on public.owner_notification_preferences;


create trigger
    owner_notification_preferences_set_updated_at

before update
on public.owner_notification_preferences

for each row

execute function
    public.set_notification_updated_at();


drop trigger if exists
    notification_deliveries_set_updated_at
on public.notification_deliveries;


create trigger
    notification_deliveries_set_updated_at

before update
on public.notification_deliveries

for each row

execute function
    public.set_notification_updated_at();



-- =========================================================
-- 8. PRÉFÉRENCES PAR DÉFAUT
-- =========================================================

insert into public.owner_notification_preferences (
    owner_account_id
)

select
    oa.id

from public.owner_accounts oa

on conflict (
    owner_account_id
)
do nothing;


create or replace function public.ensure_owner_notification_preferences()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin

    insert into public.owner_notification_preferences (
        owner_account_id
    )
    values (
        new.id
    )
    on conflict (
        owner_account_id
    )
    do nothing;

    return new;

exception
    when others then

        raise warning
            'Notification preferences creation failed for owner %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    owner_accounts_ensure_notification_preferences
on public.owner_accounts;


create trigger
    owner_accounts_ensure_notification_preferences

after insert
on public.owner_accounts

for each row

execute function
    public.ensure_owner_notification_preferences();



-- =========================================================
-- 9. CRÉER / RÉUTILISER UN ÉVÉNEMENT IDEMPOTENT
-- =========================================================

create or replace function public.ensure_notification_event(
    p_event_key text,
    p_event_type text,
    p_category text,
    p_source_type text,
    p_source_id uuid,
    p_title text,
    p_body text,
    p_priority text,
    p_action_section text,
    p_action_entity_id uuid,
    p_metadata jsonb
)
returns uuid

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

begin

    insert into public.notification_events (

        event_key,
        event_type,
        category,
        source_type,
        source_id,
        title,
        body,
        priority,
        action_section,
        action_entity_id,
        metadata

    )
    values (

        trim(p_event_key),
        trim(p_event_type),
        trim(p_category),
        trim(p_source_type),
        p_source_id,
        trim(p_title),
        trim(p_body),
        trim(p_priority),
        nullif(trim(p_action_section), ''),
        p_action_entity_id,
        coalesce(
            p_metadata,
            '{}'::jsonb
        )

    )

    on conflict (
        event_key
    )
    do update set

        event_key =
            excluded.event_key

    returning id
    into v_event_id;


    return v_event_id;

end;
$$;



-- =========================================================
-- 10. CRÉER LES LIVRAISONS EXTERNES
--
-- Appelé automatiquement après création d'une notification
-- propriétaire.
--
-- Les canaux externes ne sont créés que si le propriétaire
-- les a explicitement activés.
-- =========================================================

create or replace function public.prepare_notification_deliveries()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner public.owner_accounts%rowtype;

    v_preferences public.owner_notification_preferences%rowtype;

    v_whatsapp_destination text;

begin

    select *
    into v_owner

    from public.owner_accounts

    where id =
        new.owner_account_id;


    if not found then

        return new;

    end if;


    select *
    into v_preferences

    from public.owner_notification_preferences

    where owner_account_id =
        new.owner_account_id;


    if not found then

        insert into public.owner_notification_preferences (
            owner_account_id
        )
        values (
            new.owner_account_id
        )
        on conflict (
            owner_account_id
        )
        do nothing;

        select *
        into v_preferences

        from public.owner_notification_preferences

        where owner_account_id =
            new.owner_account_id;

    end if;


    -- -----------------------------------------------------
    -- EMAIL
    -- -----------------------------------------------------

    if
        v_preferences.email_enabled
        and
        v_preferences.email_opted_in_at is not null
    then

        if
            v_owner.email is not null
            and
            length(trim(v_owner.email)) > 3
        then

            insert into public.notification_deliveries (

                owner_notification_id,
                channel,
                provider,
                destination,
                status

            )
            values (

                new.id,
                'email',
                'resend',
                lower(trim(v_owner.email)),
                'pending'

            )
            on conflict (
                owner_notification_id,
                channel
            )
            do nothing;

        else

            insert into public.notification_deliveries (

                owner_notification_id,
                channel,
                provider,
                destination,
                status,
                skipped_at,
                last_error

            )
            values (

                new.id,
                'email',
                'resend',
                'missing-email',
                'skipped',
                now(),
                'Aucune adresse email exploitable.'

            )
            on conflict (
                owner_notification_id,
                channel
            )
            do nothing;

        end if;

    end if;


    -- -----------------------------------------------------
    -- WHATSAPP
    -- -----------------------------------------------------

    if
        v_preferences.whatsapp_enabled
        and
        v_preferences.whatsapp_opted_in_at is not null
    then

        v_whatsapp_destination :=
            coalesce(
                nullif(
                    trim(v_owner.whatsapp),
                    ''
                ),
                nullif(
                    trim(v_owner.phone_e164),
                    ''
                ),
                nullif(
                    trim(v_owner.phone),
                    ''
                )
            );


        if
            v_whatsapp_destination is not null
        then

            insert into public.notification_deliveries (

                owner_notification_id,
                channel,
                provider,
                destination,
                status

            )
            values (

                new.id,
                'whatsapp',
                'twilio_whatsapp',
                v_whatsapp_destination,
                'pending'

            )
            on conflict (
                owner_notification_id,
                channel
            )
            do nothing;

        else

            insert into public.notification_deliveries (

                owner_notification_id,
                channel,
                provider,
                destination,
                status,
                skipped_at,
                last_error

            )
            values (

                new.id,
                'whatsapp',
                'twilio_whatsapp',
                'missing-whatsapp',
                'skipped',
                now(),
                'Aucun numéro WhatsApp exploitable.'

            )
            on conflict (
                owner_notification_id,
                channel
            )
            do nothing;

        end if;

    end if;


    -- -----------------------------------------------------
    -- PUSH WEB
    --
    -- destination = owner_account_id.
    -- OneSignal utilisera cet UUID comme External ID.
    -- -----------------------------------------------------

    if
        v_preferences.push_enabled
        and
        v_preferences.push_opted_in_at is not null
    then

        insert into public.notification_deliveries (

            owner_notification_id,
            channel,
            provider,
            destination,
            status

        )
        values (

            new.id,
            'push',
            'onesignal',
            new.owner_account_id::text,
            'pending'

        )
        on conflict (
            owner_notification_id,
            channel
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'External delivery preparation failed for owner notification %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    owner_notifications_prepare_deliveries
on public.owner_notifications;


create trigger
    owner_notifications_prepare_deliveries

after insert
on public.owner_notifications

for each row

execute function
    public.prepare_notification_deliveries();



-- =========================================================
-- 11. RÉUNION PUBLIÉE -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_meeting_published()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

begin

    if
        new.status =
            'published'

        and

        old.status is distinct from
            'published'
    then

        v_event_id :=
            public.ensure_notification_event(

                'meeting:' ||
                    new.id::text ||
                    ':published',

                'meeting_published',

                'meeting',

                'meetings',

                new.id,

                'Nouvelle réunion : ' ||
                    new.title,

                'Une nouvelle réunion a été publiée. Consultez les détails et confirmez votre présence.',

                'high',

                'meetings',

                new.id,

                jsonb_build_object(
                    'meetingDate',
                    new.meeting_date,
                    'responseDeadline',
                    new.response_deadline,
                    'location',
                    new.location
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )

        select
            v_event_id,
            oa.id

        from public.owner_accounts oa

        where
            oa.status =
                'active'

        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'Meeting notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    meetings_notify_on_publish
on public.meetings;


create trigger
    meetings_notify_on_publish

after update of status
on public.meetings

for each row

execute function
    public.notify_meeting_published();



-- =========================================================
-- 12. VOTE PUBLIÉ -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_vote_published()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

begin

    if
        new.status =
            'published'

        and

        old.status is distinct from
            'published'
    then

        v_event_id :=
            public.ensure_notification_event(

                'vote:' ||
                    new.id::text ||
                    ':published',

                'vote_published',

                'vote',

                'residence_votes',

                new.id,

                'Nouveau vote : ' ||
                    new.title,

                new.question,

                'high',

                'votes',

                new.id,

                jsonb_build_object(
                    'opensAt',
                    new.opens_at,
                    'closesAt',
                    new.closes_at,
                    'allowVoteChange',
                    new.allow_vote_change
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )

        select
            v_event_id,
            e.owner_account_id

        from public.residence_vote_eligibility e

        join public.owner_accounts oa
            on oa.id =
                e.owner_account_id

        where
            e.vote_id =
                new.id

            and
            oa.status =
                'active'

        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'Vote notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    residence_votes_notify_on_publish
on public.residence_votes;


create trigger
    residence_votes_notify_on_publish

after update of status
on public.residence_votes

for each row

execute function
    public.notify_vote_published();



-- =========================================================
-- 13. APPEL DE FONDS PUBLIÉ -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_syndic_charge_published()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

begin

    if
        new.status =
            'published'

        and

        old.status is distinct from
            'published'
    then

        v_event_id :=
            public.ensure_notification_event(

                'syndic-charge:' ||
                    new.id::text ||
                    ':published',

                'syndic_charge_published',

                'syndic',

                'syndic_charge_calls',

                new.id,

                'Nouvel appel de fonds : ' ||
                    new.title,

                'Montant par lot : ' ||
                    new.default_amount::text ||
                    ' ' ||
                    new.currency ||
                    '. Échéance : ' ||
                    new.due_date::text ||
                    '.',

                'urgent',

                'syndic',

                new.id,

                jsonb_build_object(
                    'amount',
                    new.default_amount,
                    'currency',
                    new.currency,
                    'dueDate',
                    new.due_date,
                    'fiscalYear',
                    new.fiscal_year,
                    'periodLabel',
                    new.period_label
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )

        select distinct
            v_event_id,
            uc.owner_account_id

        from public.syndic_unit_charges uc

        join public.owner_accounts oa
            on oa.id =
                uc.owner_account_id

        where
            uc.charge_call_id =
                new.id

            and
            oa.status =
                'active'

        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'Syndic charge notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    syndic_charge_calls_notify_on_publish
on public.syndic_charge_calls;


create trigger
    syndic_charge_calls_notify_on_publish

after update of status
on public.syndic_charge_calls

for each row

execute function
    public.notify_syndic_charge_published();



-- =========================================================
-- 14. ANNONCE PUBLIÉE -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_announcement_published()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

    v_priority text;

begin

    if
        new.status =
            'published'

        and

        old.status is distinct from
            'published'
    then

        v_priority :=
            case
                when new.priority =
                    'urgent'
                    then 'urgent'

                when new.priority =
                    'high'
                    then 'high'

                else 'normal'
            end;


        v_event_id :=
            public.ensure_notification_event(

                'announcement:' ||
                    new.id::text ||
                    ':published',

                'announcement_published',

                'announcement',

                'residence_announcements',

                new.id,

                new.title,

                coalesce(
                    nullif(
                        trim(new.summary),
                        ''
                    ),
                    left(
                        new.content,
                        280
                    )
                ),

                v_priority,

                'announcements',

                new.id,

                jsonb_build_object(
                    'announcementCategory',
                    new.category,
                    'isPinned',
                    new.is_pinned,
                    'expiresAt',
                    new.expires_at
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )

        select distinct
            v_event_id,
            oa.id

        from public.owner_accounts oa

        where
            oa.status =
                'active'

            and exists (

                select 1

                from public.residence_announcement_targets t

                where
                    t.announcement_id =
                        new.id

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

        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'Announcement notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    residence_announcements_notify_on_publish
on public.residence_announcements;


create trigger
    residence_announcements_notify_on_publish

after update of status
on public.residence_announcements

for each row

execute function
    public.notify_announcement_published();



-- =========================================================
-- 15. DOCUMENT PUBLIÉ -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_document_published()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

begin

    if
        new.status =
            'published'

        and

        old.status is distinct from
            'published'
    then

        v_event_id :=
            public.ensure_notification_event(

                'document:' ||
                    new.id::text ||
                    ':published',

                'document_published',

                'document',

                'residence_documents',

                new.id,

                'Nouveau document : ' ||
                    new.title,

                coalesce(
                    nullif(
                        trim(new.description),
                        ''
                    ),
                    'Un nouveau document privé est disponible dans votre espace propriétaire.'
                ),

                'normal',

                'documents',

                new.id,

                jsonb_build_object(
                    'documentCategory',
                    new.category,
                    'originalFilename',
                    new.original_filename,
                    'mimeType',
                    new.mime_type,
                    'fileSizeBytes',
                    new.file_size_bytes
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )

        select distinct
            v_event_id,
            oa.id

        from public.owner_accounts oa

        where
            oa.status =
                'active'

            and exists (

                select 1

                from public.residence_document_targets t

                where
                    t.document_id =
                        new.id

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

        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;

    end if;


    return new;

exception
    when others then

        raise warning
            'Document notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    residence_documents_notify_on_publish
on public.residence_documents;


create trigger
    residence_documents_notify_on_publish

after update of status
on public.residence_documents

for each row

execute function
    public.notify_document_published();



-- =========================================================
-- 16. PAIEMENT SYNDIC -> NOTIFICATIONS
-- =========================================================

create or replace function public.notify_syndic_payment_status()
returns trigger

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_event_id uuid;

    v_owner_status text;

begin

    select oa.status
    into v_owner_status

    from public.owner_accounts oa

    where oa.id =
        new.owner_account_id;


    if
        v_owner_status <>
        'active'
    then

        return new;

    end if;


    -- Paiement confirmé à la création.
    if
        tg_op =
        'INSERT'

        and

        new.status =
        'confirmed'
    then

        v_event_id :=
            public.ensure_notification_event(

                'syndic-payment:' ||
                    new.id::text ||
                    ':confirmed',

                'syndic_payment_confirmed',

                'syndic',

                'syndic_payments',

                new.id,

                'Paiement syndic enregistré',

                'Votre paiement de ' ||
                    new.amount::text ||
                    ' ' ||
                    new.currency ||
                    ' a été enregistré.',

                'normal',

                'syndic',

                new.id,

                jsonb_build_object(
                    'amount',
                    new.amount,
                    'currency',
                    new.currency,
                    'paymentDate',
                    new.payment_date,
                    'paymentMethod',
                    new.payment_method,
                    'reference',
                    new.reference
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )
        values (
            v_event_id,
            new.owner_account_id
        )
        on conflict (
            event_id,
            owner_account_id
        )
        do nothing;


        return new;

    end if;


    -- Paiement extourné ultérieurement.
    if
        tg_op =
        'UPDATE'
    then

        if
            new.status =
                'reversed'

            and

            old.status is distinct from
                'reversed'
        then

            v_event_id :=
            public.ensure_notification_event(

                'syndic-payment:' ||
                    new.id::text ||
                    ':reversed',

                'syndic_payment_reversed',

                'syndic',

                'syndic_payments',

                new.id,

                'Correction d''un paiement syndic',

                'Un paiement de ' ||
                    new.amount::text ||
                    ' ' ||
                    new.currency ||
                    ' a été extourné. Consultez votre situation syndic.',

                'urgent',

                'syndic',

                new.id,

                jsonb_build_object(
                    'amount',
                    new.amount,
                    'currency',
                    new.currency,
                    'paymentDate',
                    new.payment_date,
                    'reference',
                    new.reference,
                    'reversalReason',
                    new.reversal_reason
                )

            );


        insert into public.owner_notifications (
            event_id,
            owner_account_id
        )
        values (
            v_event_id,
            new.owner_account_id
        )
            on conflict (
                event_id,
                owner_account_id
            )
            do nothing;

        end if;

    end if;


    return new;

exception
    when others then

        raise warning
            'Syndic payment notification generation failed for %: %',
            new.id,
            sqlerrm;

        return new;

end;
$$;


drop trigger if exists
    syndic_payments_notify_on_insert
on public.syndic_payments;


create trigger
    syndic_payments_notify_on_insert

after insert
on public.syndic_payments

for each row

execute function
    public.notify_syndic_payment_status();


drop trigger if exists
    syndic_payments_notify_on_update
on public.syndic_payments;


create trigger
    syndic_payments_notify_on_update

after update of status
on public.syndic_payments

for each row

execute function
    public.notify_syndic_payment_status();



-- =========================================================
-- 17. RLS
-- =========================================================

alter table public.owner_notification_preferences
    enable row level security;


alter table public.notification_events
    enable row level security;


alter table public.owner_notifications
    enable row level security;


alter table public.notification_deliveries
    enable row level security;


alter table public.notification_delivery_attempts
    enable row level security;


alter table public.notification_provider_events
    enable row level security;



-- =========================================================
-- 18. PRÉFÉRENCES — PROPRIÉTAIRE / ADMIN
-- =========================================================

drop policy if exists
    "owner_notification_preferences_owner_select"
on public.owner_notification_preferences;


create policy
    "owner_notification_preferences_owner_select"

on public.owner_notification_preferences

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_notification_preferences.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);


drop policy if exists
    "owner_notification_preferences_admin_select"
on public.owner_notification_preferences;


create policy
    "owner_notification_preferences_admin_select"

on public.owner_notification_preferences

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 19. EVENTS — PROPRIÉTAIRE / ADMIN
-- =========================================================

drop policy if exists
    "notification_events_owner_select"
on public.notification_events;


create policy
    "notification_events_owner_select"

on public.notification_events

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_notifications n

        join public.owner_accounts oa
            on oa.id =
                n.owner_account_id

        where
            n.event_id =
                notification_events.id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);


drop policy if exists
    "notification_events_admin_select"
on public.notification_events;


create policy
    "notification_events_admin_select"

on public.notification_events

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 20. INBOX — PROPRIÉTAIRE / ADMIN
-- =========================================================

drop policy if exists
    "owner_notifications_owner_select"
on public.owner_notifications;


create policy
    "owner_notifications_owner_select"

on public.owner_notifications

for select

to authenticated

using (

    exists (

        select 1

        from public.owner_accounts oa

        where
            oa.id =
                owner_notifications.owner_account_id

            and
            oa.auth_user_id =
                (select auth.uid())

            and
            oa.status =
                'active'

    )

);


drop policy if exists
    "owner_notifications_admin_select"
on public.owner_notifications;


create policy
    "owner_notifications_admin_select"

on public.owner_notifications

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 21. LIVRAISONS / ATTEMPTS / PROVIDER EVENTS — ADMIN
-- =========================================================

drop policy if exists
    "notification_deliveries_admin_select"
on public.notification_deliveries;


create policy
    "notification_deliveries_admin_select"

on public.notification_deliveries

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "notification_delivery_attempts_admin_select"
on public.notification_delivery_attempts;


create policy
    "notification_delivery_attempts_admin_select"

on public.notification_delivery_attempts

for select

to authenticated

using (
    (select public.is_admin())
);


drop policy if exists
    "notification_provider_events_admin_select"
on public.notification_provider_events;


create policy
    "notification_provider_events_admin_select"

on public.notification_provider_events

for select

to authenticated

using (
    (select public.is_admin())
);



-- =========================================================
-- 22. RPC PROPRIÉTAIRE : MARQUER UNE NOTIFICATION COMME LUE
-- =========================================================

create or replace function public.owner_mark_notification_read(
    p_notification_id uuid
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_notification public.owner_notifications%rowtype;

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


    update public.owner_notifications

    set
        seen_at =
            coalesce(
                seen_at,
                now()
            ),

        opened_at =
            coalesce(
                opened_at,
                now()
            ),

        read_at =
            coalesce(
                read_at,
                now()
            )

    where
        id =
            p_notification_id

        and
        owner_account_id =
            v_owner_account_id

    returning *
    into v_notification;


    if not found then

        raise exception
            'Notification introuvable ou non autorisée.';

    end if;


    return jsonb_build_object(

        'success',
        true,

        'notificationId',
        v_notification.id,

        'readAt',
        v_notification.read_at

    );

end;
$$;



-- =========================================================
-- 23. RPC PROPRIÉTAIRE : TOUT MARQUER COMME LU
-- =========================================================

create or replace function public.owner_mark_all_notifications_read()
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_count integer;

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


    update public.owner_notifications

    set
        seen_at =
            coalesce(
                seen_at,
                now()
            ),

        read_at =
            coalesce(
                read_at,
                now()
            )

    where
        owner_account_id =
            v_owner_account_id

        and
        read_at is null;


    get diagnostics
        v_count =
            row_count;


    return jsonb_build_object(

        'success',
        true,

        'updated',
        v_count

    );

end;
$$;



-- =========================================================
-- 24. RPC PROPRIÉTAIRE : COMPTEUR NON LU
-- =========================================================

create or replace function public.owner_get_unread_notification_count()
returns integer

language plpgsql

stable

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_count integer;

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

        return 0;

    end if;


    select count(*)
    into v_count

    from public.owner_notifications n

    where
        n.owner_account_id =
            v_owner_account_id

        and
        n.read_at is null;


    return v_count;

end;
$$;



-- =========================================================
-- 25. RPC PROPRIÉTAIRE : PRÉFÉRENCES
-- =========================================================

create or replace function public.owner_get_notification_preferences()
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

    v_pref public.owner_notification_preferences%rowtype;

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


    insert into public.owner_notification_preferences (
        owner_account_id
    )
    values (
        v_owner_account_id
    )
    on conflict (
        owner_account_id
    )
    do nothing;


    select *
    into v_pref

    from public.owner_notification_preferences

    where owner_account_id =
        v_owner_account_id;


    return jsonb_build_object(

        'ownerAccountId',
        v_owner_account_id,

        'inAppEnabled',
        v_pref.in_app_enabled,

        'emailEnabled',
        v_pref.email_enabled,

        'whatsappEnabled',
        v_pref.whatsapp_enabled,

        'pushEnabled',
        v_pref.push_enabled,

        'digestMode',
        v_pref.digest_mode,

        'quietHoursStart',
        v_pref.quiet_hours_start,

        'quietHoursEnd',
        v_pref.quiet_hours_end,

        'timezone',
        v_pref.timezone

    );

end;
$$;



create or replace function public.owner_update_notification_preferences(
    p_email_enabled boolean,
    p_whatsapp_enabled boolean,
    p_push_enabled boolean,
    p_digest_mode text default 'immediate',
    p_quiet_hours_start time default null,
    p_quiet_hours_end time default null,
    p_timezone text default 'Africa/Casablanca'
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_owner_account_id uuid;

begin

    if
        p_digest_mode not in (
            'immediate',
            'daily'
        )
    then

        raise exception
            'Mode de notification invalide.';

    end if;


    if
        p_timezone is null

        or
        length(trim(p_timezone)) = 0
    then

        raise exception
            'Fuseau horaire invalide.';

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


    insert into public.owner_notification_preferences as pref (

        owner_account_id,
        email_enabled,
        whatsapp_enabled,
        push_enabled,
        email_opted_in_at,
        email_opted_out_at,
        whatsapp_opted_in_at,
        whatsapp_opted_out_at,
        push_opted_in_at,
        push_opted_out_at,
        digest_mode,
        quiet_hours_start,
        quiet_hours_end,
        timezone

    )
    values (

        v_owner_account_id,
        coalesce(p_email_enabled, false),
        coalesce(p_whatsapp_enabled, false),
        coalesce(p_push_enabled, false),

        case
            when coalesce(p_email_enabled, false)
                then now()
            else null
        end,

        case
            when coalesce(p_email_enabled, false)
                then null
            else now()
        end,

        case
            when coalesce(p_whatsapp_enabled, false)
                then now()
            else null
        end,

        case
            when coalesce(p_whatsapp_enabled, false)
                then null
            else now()
        end,

        case
            when coalesce(p_push_enabled, false)
                then now()
            else null
        end,

        case
            when coalesce(p_push_enabled, false)
                then null
            else now()
        end,

        p_digest_mode,
        p_quiet_hours_start,
        p_quiet_hours_end,
        trim(p_timezone)

    )

    on conflict (
        owner_account_id
    )

    do update set

        email_enabled =
            excluded.email_enabled,

        whatsapp_enabled =
            excluded.whatsapp_enabled,

        push_enabled =
            excluded.push_enabled,

        email_opted_in_at =
            case
                when excluded.email_enabled
                    then coalesce(
                        pref.email_opted_in_at,
                        now()
                    )
                else
                    pref.email_opted_in_at
            end,

        email_opted_out_at =
            case
                when excluded.email_enabled
                    then null
                else now()
            end,

        whatsapp_opted_in_at =
            case
                when excluded.whatsapp_enabled
                    then coalesce(
                        pref.whatsapp_opted_in_at,
                        now()
                    )
                else
                    pref.whatsapp_opted_in_at
            end,

        whatsapp_opted_out_at =
            case
                when excluded.whatsapp_enabled
                    then null
                else now()
            end,

        push_opted_in_at =
            case
                when excluded.push_enabled
                    then coalesce(
                        pref.push_opted_in_at,
                        now()
                    )
                else
                    pref.push_opted_in_at
            end,

        push_opted_out_at =
            case
                when excluded.push_enabled
                    then null
                else now()
            end,

        digest_mode =
            excluded.digest_mode,

        quiet_hours_start =
            excluded.quiet_hours_start,

        quiet_hours_end =
            excluded.quiet_hours_end,

        timezone =
            excluded.timezone;


    return public.owner_get_notification_preferences();

end;
$$;



-- =========================================================
-- 26. RPC SERVICE : CLAIM ATOMIQUE DES LIVRAISONS
--
-- Edge Function appelle cette RPC avec service_role.
-- FOR UPDATE SKIP LOCKED permet plusieurs workers.
-- =========================================================

create or replace function public.service_claim_notification_deliveries(
    p_limit integer default 20
)
returns setof public.notification_deliveries

language plpgsql

security definer

set search_path = ''

as $$

begin

    if
        coalesce(
            auth.role(),
            ''
        ) <>
        'service_role'
    then

        raise exception
            'Service role requis.';

    end if;


    return query

    with picked as (

        select d.id

        from public.notification_deliveries d

        where
            d.status in (
                'pending',
                'failed'
            )

            and
            d.scheduled_for <= now()

            and
            d.next_attempt_at <= now()

            and
            d.attempt_count <
                d.max_attempts

        order by
            d.next_attempt_at asc,
            d.created_at asc

        for update
        skip locked

        limit greatest(
            1,
            least(
                coalesce(
                    p_limit,
                    20
                ),
                100
            )
        )

    )

    update public.notification_deliveries d

    set
        status =
            'processing',

        processing_started_at =
            now(),

        attempt_count =
            d.attempt_count +
            1

    from picked p

    where
        d.id =
            p.id

    returning d.*;

end;
$$;



-- =========================================================
-- 27. RPC SERVICE : FINALISER UNE LIVRAISON
-- =========================================================

create or replace function public.service_finish_notification_delivery(
    p_delivery_id uuid,
    p_status text,
    p_provider_message_id text default null,
    p_last_error text default null,
    p_next_attempt_at timestamptz default null
)
returns jsonb

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_delivery public.notification_deliveries%rowtype;

begin

    if
        coalesce(
            auth.role(),
            ''
        ) <>
        'service_role'
    then

        raise exception
            'Service role requis.';

    end if;


    if
        p_status not in (
            'sent',
            'delivered',
            'failed',
            'skipped',
            'cancelled'
        )
    then

        raise exception
            'Statut de livraison invalide.';

    end if;


    update public.notification_deliveries

    set
        status =
            p_status,

        provider_message_id =
            coalesce(
                p_provider_message_id,
                provider_message_id
            ),

        last_error =
            p_last_error,

        processing_started_at =
            null,

        sent_at =
            case
                when p_status in (
                    'sent',
                    'delivered'
                )
                    then coalesce(
                        sent_at,
                        now()
                    )
                else sent_at
            end,

        delivered_at =
            case
                when p_status =
                    'delivered'
                    then coalesce(
                        delivered_at,
                        now()
                    )
                else delivered_at
            end,

        failed_at =
            case
                when p_status =
                    'failed'
                    then now()
                else null
            end,

        skipped_at =
            case
                when p_status =
                    'skipped'
                    then now()
                else skipped_at
            end,

        next_attempt_at =
            case
                when p_status =
                    'failed'
                    then coalesce(
                        p_next_attempt_at,
                        now() +
                        interval '5 minutes'
                    )
                else next_attempt_at
            end

    where id =
        p_delivery_id

    returning *
    into v_delivery;


    if not found then

        raise exception
            'Livraison introuvable.';

    end if;


    return jsonb_build_object(

        'success',
        true,

        'deliveryId',
        v_delivery.id,

        'status',
        v_delivery.status,

        'attemptCount',
        v_delivery.attempt_count,

        'providerMessageId',
        v_delivery.provider_message_id

    );

end;
$$;



-- =========================================================
-- 28. RPC SERVICE : RÉCUPÉRER LES JOBS BLOQUÉS
-- =========================================================

create or replace function public.service_requeue_stale_notification_deliveries()
returns integer

language plpgsql

security definer

set search_path = ''

as $$

declare

    v_count integer;

begin

    if
        coalesce(
            auth.role(),
            ''
        ) <>
        'service_role'
    then

        raise exception
            'Service role requis.';

    end if;


    update public.notification_deliveries

    set
        status =
            'failed',

        failed_at =
            now(),

        processing_started_at =
            null,

        last_error =
            'Worker timeout / stale processing.',

        next_attempt_at =
            now() +
            interval '2 minutes'

    where
        status =
            'processing'

        and
        processing_started_at <
            now() -
            interval '10 minutes';


    get diagnostics
        v_count =
            row_count;


    return v_count;

end;
$$;



-- =========================================================
-- 29. RPC ADMIN : STATISTIQUES GLOBALES
-- =========================================================

create or replace function public.admin_get_notification_stats()
returns jsonb

language plpgsql

stable

security definer

set search_path = ''

as $$

declare

    v_notifications bigint;

    v_unread bigint;

    v_pending bigint;

    v_failed bigint;

    v_sent bigint;

begin

    if not public.is_admin() then

        raise exception
            'Accès administrateur requis.';

    end if;


    select count(*)
    into v_notifications

    from public.owner_notifications;


    select count(*)
    into v_unread

    from public.owner_notifications

    where read_at is null;


    select count(*)
    into v_pending

    from public.notification_deliveries

    where status in (
        'pending',
        'processing'
    );


    select count(*)
    into v_failed

    from public.notification_deliveries

    where status =
        'failed';


    select count(*)
    into v_sent

    from public.notification_deliveries

    where status in (
        'sent',
        'delivered'
    );


    return jsonb_build_object(

        'notifications',
        v_notifications,

        'unread',
        v_unread,

        'pendingDeliveries',
        v_pending,

        'failedDeliveries',
        v_failed,

        'successfulDeliveries',
        v_sent

    );

end;
$$;



-- =========================================================
-- 30. PRIVILÈGES TABLES
-- =========================================================

revoke all
on public.owner_notification_preferences
from anon;


revoke all
on public.notification_events
from anon;


revoke all
on public.owner_notifications
from anon;


revoke all
on public.notification_deliveries
from anon;


revoke all
on public.notification_delivery_attempts
from anon;


revoke all
on public.notification_provider_events
from anon;



grant select
on public.owner_notification_preferences
to authenticated;


grant select
on public.notification_events
to authenticated;


grant select
on public.owner_notifications
to authenticated;


grant select
on public.notification_deliveries
to authenticated;


grant select
on public.notification_delivery_attempts
to authenticated;


grant select
on public.notification_provider_events
to authenticated;



grant all
on public.owner_notification_preferences
to service_role;


grant all
on public.notification_events
to service_role;


grant all
on public.owner_notifications
to service_role;


grant all
on public.notification_deliveries
to service_role;


grant all
on public.notification_delivery_attempts
to service_role;


grant all
on public.notification_provider_events
to service_role;



-- =========================================================
-- 31. PRIVILÈGES RPC / HELPERS
-- =========================================================

revoke all
on function public.ensure_notification_event(
    text,
    text,
    text,
    text,
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    jsonb
)
from public;


revoke all
on function public.ensure_notification_event(
    text,
    text,
    text,
    text,
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    jsonb
)
from anon;


revoke all
on function public.ensure_notification_event(
    text,
    text,
    text,
    text,
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    jsonb
)
from authenticated;



revoke all
on function public.owner_mark_notification_read(uuid)
from public;


revoke all
on function public.owner_mark_notification_read(uuid)
from anon;


grant execute
on function public.owner_mark_notification_read(uuid)
to authenticated;



revoke all
on function public.owner_mark_all_notifications_read()
from public;


revoke all
on function public.owner_mark_all_notifications_read()
from anon;


grant execute
on function public.owner_mark_all_notifications_read()
to authenticated;



revoke all
on function public.owner_get_unread_notification_count()
from public;


revoke all
on function public.owner_get_unread_notification_count()
from anon;


grant execute
on function public.owner_get_unread_notification_count()
to authenticated;



revoke all
on function public.owner_get_notification_preferences()
from public;


revoke all
on function public.owner_get_notification_preferences()
from anon;


grant execute
on function public.owner_get_notification_preferences()
to authenticated;



revoke all
on function public.owner_update_notification_preferences(
    boolean,
    boolean,
    boolean,
    text,
    time,
    time,
    text
)
from public;


revoke all
on function public.owner_update_notification_preferences(
    boolean,
    boolean,
    boolean,
    text,
    time,
    time,
    text
)
from anon;


grant execute
on function public.owner_update_notification_preferences(
    boolean,
    boolean,
    boolean,
    text,
    time,
    time,
    text
)
to authenticated;



revoke all
on function public.service_claim_notification_deliveries(integer)
from public;


revoke all
on function public.service_claim_notification_deliveries(integer)
from anon;


revoke all
on function public.service_claim_notification_deliveries(integer)
from authenticated;


grant execute
on function public.service_claim_notification_deliveries(integer)
to service_role;



revoke all
on function public.service_finish_notification_delivery(
    uuid,
    text,
    text,
    text,
    timestamptz
)
from public;


revoke all
on function public.service_finish_notification_delivery(
    uuid,
    text,
    text,
    text,
    timestamptz
)
from anon;


revoke all
on function public.service_finish_notification_delivery(
    uuid,
    text,
    text,
    text,
    timestamptz
)
from authenticated;


grant execute
on function public.service_finish_notification_delivery(
    uuid,
    text,
    text,
    text,
    timestamptz
)
to service_role;



revoke all
on function public.service_requeue_stale_notification_deliveries()
from public;


revoke all
on function public.service_requeue_stale_notification_deliveries()
from anon;


revoke all
on function public.service_requeue_stale_notification_deliveries()
from authenticated;


grant execute
on function public.service_requeue_stale_notification_deliveries()
to service_role;



revoke all
on function public.admin_get_notification_stats()
from public;


revoke all
on function public.admin_get_notification_stats()
from anon;


grant execute
on function public.admin_get_notification_stats()
to authenticated;


grant execute
on function public.admin_get_notification_stats()
to service_role;



-- =========================================================
-- 32. SERVICE ROLE POUR LES FONCTIONS INTERNES DE TRIGGER
-- =========================================================

grant execute
on function public.ensure_notification_event(
    text,
    text,
    text,
    text,
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    jsonb
)
to service_role;
