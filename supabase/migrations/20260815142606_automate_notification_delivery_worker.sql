-- =========================================================
-- MIRADOR GOLF 1
-- Notifications V2 — automatic delivery worker
-- =========================================================

create extension if not exists pg_net
with schema extensions;

create extension if not exists pg_cron;


-- Supprime une éventuelle ancienne version du job.
do $$

declare
    v_job_id bigint;

begin

    select jobid
    into v_job_id

    from cron.job

    where jobname =
        'mirador-notification-worker'

    limit 1;


    if v_job_id is not null then

        perform cron.unschedule(
            v_job_id
        );

    end if;

end;
$$;


-- Exécution toutes les minutes.
select cron.schedule(
    'mirador-notification-worker',
    '* * * * *',

    $cron$

    select net.http_post(

        url :=
            'https://hanbgkefeqgstnsaapel.supabase.co/functions/v1/process-notification-deliveries',

        headers :=
            jsonb_build_object(

                'Content-Type',
                'application/json',

                'x-worker-secret',
                (
                    select decrypted_secret

                    from vault.decrypted_secrets

                    where name =
                        'notification_worker_secret'

                    limit 1
                )
            ),

        body :=
            jsonb_build_object(
                'limit',
                20
            ),

        timeout_milliseconds :=
            10000
    );

    $cron$
);