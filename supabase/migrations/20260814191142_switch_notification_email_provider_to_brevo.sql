-- =========================================================
-- MIRADOR GOLF 1
-- Notification email provider: Resend -> Brevo
--
-- Centralise le provider réel par canal pour que
-- notification_deliveries / attempts restent cohérents.
-- =========================================================

update public.notification_deliveries
set provider = 'brevo'
where channel = 'email'
  and provider <> 'brevo';


create or replace function public.normalize_notification_delivery_provider()
returns trigger

language plpgsql

set search_path = ''

as $$

begin

    if new.channel = 'email' then

        new.provider :=
            'brevo';

    elsif new.channel = 'whatsapp' then

        new.provider :=
            'twilio_whatsapp';

    elsif new.channel = 'push' then

        new.provider :=
            'onesignal';

    end if;


    return new;

end;
$$;


drop trigger if exists
    notification_deliveries_normalize_provider
on public.notification_deliveries;


create trigger
    notification_deliveries_normalize_provider

before insert
or update of channel, provider

on public.notification_deliveries

for each row

execute function
    public.normalize_notification_delivery_provider();