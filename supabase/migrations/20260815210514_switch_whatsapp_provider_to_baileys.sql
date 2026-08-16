-- ============================================================
-- MIRADOR GOLF 1
-- Notifications V2
-- Switch WhatsApp delivery provider:
-- twilio_whatsapp -> baileys
-- ============================================================

do $$
declare
    v_signature text;
    v_oid oid;
    v_definition text;
begin

    foreach v_signature in array array[
        'public.normalize_notification_delivery_provider()',
        'public.prepare_notification_deliveries()'
    ]
    loop

        v_oid := to_regprocedure(v_signature);

        if v_oid is null then
            raise exception
                'Required function not found: %',
                v_signature;
        end if;

        select pg_get_functiondef(v_oid)
        into v_definition;

        if position(
            'twilio_whatsapp'
            in v_definition
        ) > 0 then

            execute replace(
                v_definition,
                'twilio_whatsapp',
                'baileys'
            );

        end if;

    end loop;

end;
$$;


-- ------------------------------------------------------------
-- Normalize existing queued WhatsApp deliveries if any.
-- At migration time there may be zero rows; this remains
-- intentionally idempotent.
-- ------------------------------------------------------------

update public.notification_deliveries
set provider = 'baileys'
where channel = 'whatsapp'
  and provider = 'twilio_whatsapp';


-- ------------------------------------------------------------
-- Verification: both active functions must no longer contain
-- the legacy provider.
-- ------------------------------------------------------------

do $$
declare
    v_count integer;
begin

    select count(*)
    into v_count
    from pg_proc p
    join pg_namespace n
        on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and p.proname in (
          'normalize_notification_delivery_provider',
          'prepare_notification_deliveries'
      )
      and pg_get_functiondef(p.oid)
          ilike '%twilio_whatsapp%';

    if v_count <> 0 then
        raise exception
            'Legacy provider twilio_whatsapp still present in % function(s).',
            v_count;
    end if;

end;
$$;